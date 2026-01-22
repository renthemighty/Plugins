<?php
/**
 * Plugin Name: SPVS Cost & Profit for WooCommerce
 * Description: Adds product cost, computes profit per order, TCOP/Retail inventory totals with CSV export/import, monthly profit reports, and COG import.
 * Version: 3.0.3
 * Author: Megatron
 * License: GPL-2.0+
 * License URI: https://www.gnu.org/licenses/gpl-2.0.txt
 * Text Domain: spvs-cost-profit
 * Requires at least: 6.0
 * Requires PHP: 7.4
 * WC requires at least: 7.0
 * WC tested up to: 9.1
 */

if ( ! defined( 'ABSPATH' ) ) { exit; }

if ( ! class_exists( 'SPVS_Cost_Profit' ) ) :

final class SPVS_Cost_Profit {

    const PRODUCT_COST_META       = '_spvs_cost_price';
    const ORDER_TOTAL_PROFIT_META = '_spvs_total_profit';
    const ORDER_LINE_PROFIT_META  = '_spvs_line_profit';

    // Inventory totals cache & per-product cached totals
    const INVENTORY_TOTALS_OPTION   = 'spvs_inventory_totals_cache';
    const PRODUCT_COST_TOTAL_META   = '_spvs_stock_cost_total';
    const PRODUCT_RETAIL_TOTAL_META = '_spvs_stock_retail_total';
    const RECALC_LOCK_TRANSIENT     = 'spvs_inventory_recalc_lock';

    // Import diagnostics
    const IMPORT_MISSES_TRANSIENT   = 'spvs_cost_import_misses';

    // Data integrity & audit
    const DB_VERSION                = '3.0.3';
    const BACKUP_TRANSIENT_PREFIX   = 'spvs_backup_';
    const INTEGRITY_CHECK_OPTION    = 'spvs_last_integrity_check';
    const AUDIT_LOG_RETENTION_DAYS  = 90; // Keep audit logs for 90 days

    private static $instance = null;

    public static function instance() {
        if ( null === self::$instance ) { self::$instance = new self(); }
        return self::$instance;
    }

    private function __construct() {
        add_action( 'init', array( $this, 'maybe_init' ), 20 );
        add_action( 'before_woocommerce_init', array( $this, 'declare_hpos_compat' ) );
        add_action( 'plugins_loaded', array( $this, 'check_db_version' ) );
    }

    public function check_db_version() {
        $installed_version = get_option( 'spvs_db_version', '0' );
        if ( version_compare( $installed_version, self::DB_VERSION, '<' ) ) {
            $this->create_audit_table();
            update_option( 'spvs_db_version', self::DB_VERSION );
        }
    }

    /** ---------------- Data Integrity & Audit System ---------------- */
    private function create_audit_table() {
        global $wpdb;
        $table_name = $wpdb->prefix . 'spvs_cost_audit';
        $charset_collate = $wpdb->get_charset_collate();

        $sql = "CREATE TABLE IF NOT EXISTS $table_name (
            id bigint(20) unsigned NOT NULL AUTO_INCREMENT,
            product_id bigint(20) unsigned NOT NULL,
            action varchar(50) NOT NULL,
            old_cost decimal(19,4) DEFAULT NULL,
            new_cost decimal(19,4) DEFAULT NULL,
            user_id bigint(20) unsigned DEFAULT NULL,
            source varchar(50) NOT NULL DEFAULT 'manual',
            metadata text DEFAULT NULL,
            created_at datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (id),
            KEY product_id (product_id),
            KEY created_at (created_at),
            KEY action (action)
        ) $charset_collate;";

        require_once( ABSPATH . 'wp-admin/includes/upgrade.php' );
        dbDelta( $sql );
    }

    private function log_cost_change( $product_id, $action, $old_cost, $new_cost, $source = 'manual', $metadata = array() ) {
        global $wpdb;
        $table_name = $wpdb->prefix . 'spvs_cost_audit';

        // Validate inputs
        $product_id = absint( $product_id );
        if ( ! $product_id ) return false;

        $old_cost = $old_cost !== '' && $old_cost !== null ? wc_format_decimal( $old_cost, 4 ) : null;
        $new_cost = $new_cost !== '' && $new_cost !== null ? wc_format_decimal( $new_cost, 4 ) : null;

        $user_id = get_current_user_id();
        $metadata_json = ! empty( $metadata ) ? wp_json_encode( $metadata ) : null;

        $wpdb->insert(
            $table_name,
            array(
                'product_id'  => $product_id,
                'action'      => sanitize_text_field( $action ),
                'old_cost'    => $old_cost,
                'new_cost'    => $new_cost,
                'user_id'     => $user_id ? $user_id : null,
                'source'      => sanitize_text_field( $source ),
                'metadata'    => $metadata_json,
                'created_at'  => current_time( 'mysql' ),
            ),
            array( '%d', '%s', '%s', '%s', '%d', '%s', '%s', '%s' )
        );

        return $wpdb->insert_id;
    }

    private function cleanup_old_audit_logs() {
        global $wpdb;
        $table_name = $wpdb->prefix . 'spvs_cost_audit';
        $days = self::AUDIT_LOG_RETENTION_DAYS;

        $wpdb->query( $wpdb->prepare(
            "DELETE FROM $table_name WHERE created_at < DATE_SUB(NOW(), INTERVAL %d DAY)",
            $days
        ) );
    }

    private function create_backup_before_bulk_operation( $product_ids, $operation = 'bulk_edit' ) {
        $backup = array();
        foreach ( $product_ids as $product_id ) {
            $cost = $this->get_product_cost_raw( $product_id );
            if ( $cost !== '' ) {
                $backup[ $product_id ] = $cost;
            }
        }

        if ( ! empty( $backup ) ) {
            $backup_key = self::BACKUP_TRANSIENT_PREFIX . $operation . '_' . time();
            set_transient( $backup_key, $backup, HOUR_IN_SECONDS * 24 ); // Keep for 24 hours
            return $backup_key;
        }

        return false;
    }

    private function restore_from_backup( $backup_key ) {
        $backup = get_transient( $backup_key );
        if ( ! $backup || ! is_array( $backup ) ) {
            return false;
        }

        $restored = 0;
        foreach ( $backup as $product_id => $cost ) {
            update_post_meta( $product_id, self::PRODUCT_COST_META, $cost );
            $this->log_cost_change( $product_id, 'restore_backup', null, $cost, 'system', array( 'backup_key' => $backup_key ) );
            $restored++;
        }

        return $restored;
    }

    public function declare_hpos_compat() {
        if ( class_exists( '\Automattic\WooCommerce\Utilities\FeaturesUtil' ) ) {
            \Automattic\WooCommerce\Utilities\FeaturesUtil::declare_compatibility( 'custom_order_tables', __FILE__, true );
        }
    }

    public function maybe_init() {
        if ( ! class_exists( 'WooCommerce' ) ) return;

        /** Product admin: Cost field */
        add_action( 'woocommerce_product_options_pricing', array( $this, 'add_product_cost_field' ) );
        add_action( 'woocommerce_admin_process_product_object', array( $this, 'save_product_cost_field' ) );

        /** Variations */
        add_action( 'woocommerce_variation_options_pricing', array( $this, 'add_variation_cost_field' ), 10, 3 );
        add_action( 'woocommerce_save_product_variation', array( $this, 'save_variation_cost_field' ), 10, 2 );

        /** Quick Edit */
        add_action( 'woocommerce_product_quick_edit_end', array( $this, 'add_quick_edit_cost_field' ) );
        add_action( 'woocommerce_product_quick_edit_save', array( $this, 'save_quick_edit_cost_field' ) );
        add_action( 'manage_product_posts_custom_column', array( $this, 'add_cost_to_product_column_data' ), 10, 2 );

        /** Bulk Edit */
        add_action( 'woocommerce_product_bulk_edit_end', array( $this, 'add_bulk_edit_cost_field' ) );
        add_action( 'woocommerce_product_bulk_edit_save', array( $this, 'save_bulk_edit_cost_field' ) );

        /** Profit at checkout & recalcs */
        add_action( 'woocommerce_checkout_create_order_line_item', array( $this, 'add_line_item_profit_on_checkout' ), 10, 4 );
        add_action( 'woocommerce_checkout_order_created', array( $this, 'recalculate_order_total_profit' ) );
        add_action( 'woocommerce_order_refunded', array( $this, 'recalculate_order_total_profit_by_id' ), 10, 2 );
        add_action( 'woocommerce_update_order', array( $this, 'recalculate_order_total_profit' ), 10, 1 );

        /** Order screen: Profit meta box */
        add_action( 'add_meta_boxes', array( $this, 'add_profit_metabox' ) );

        /** Orders list columns (classic + HPOS) */
        add_filter( 'manage_edit-shop_order_columns', array( $this, 'add_orders_list_profit_column_legacy' ), 20 );
        add_action( 'manage_shop_order_posts_custom_column', array( $this, 'render_orders_list_profit_column_legacy' ), 10, 2 );
        add_filter( 'manage_woocommerce_page_wc-orders_columns', array( $this, 'add_orders_list_profit_column_hpos' ), 20 );
        add_action( 'manage_woocommerce_page_wc-orders_custom_column', array( $this, 'render_orders_list_profit_column_hpos' ), 10, 2 );
        add_filter( 'woocommerce_shop_order_list_table_columns', array( $this, 'add_orders_list_profit_column_shop_table' ), 20 );
        add_action( 'woocommerce_shop_order_list_table_custom_column', array( $this, 'render_orders_list_profit_column_shop_table' ), 10, 2 );
        add_filter( 'manage_edit-shop_order_sortable_columns', array( $this, 'make_profit_column_sortable' ) );
        add_action( 'pre_get_posts', array( $this, 'orders_list_sort_by_profit_query' ) );

        /** TCOP bar on Orders screen */
        add_action( 'in_admin_header', array( $this, 'maybe_render_tcop_bar' ) );

        /** Recalc handler & CSV export/import */
        add_action( 'admin_post_spvs_recalc_inventory', array( $this, 'handle_recalc_inventory' ) );
        add_action( 'admin_post_spvs_export_inventory_csv', array( $this, 'export_inventory_csv' ) );
        add_action( 'admin_post_spvs_import_costs_csv', array( $this, 'import_costs_csv' ) );
        add_action( 'admin_post_spvs_cost_template_csv', array( $this, 'download_cost_template_csv' ) );
        add_action( 'admin_post_spvs_cost_import_misses', array( $this, 'download_cost_import_misses' ) );
        add_action( 'admin_post_spvs_cost_missing_csv', array( $this, 'download_missing_cost_csv' ) );

        /** Profit report export */
        add_action( 'admin_post_spvs_export_profit_report', array( $this, 'export_profit_report_csv' ) );
        add_action( 'admin_post_spvs_export_top_products', array( $this, 'export_top_products_csv' ) );

        /** COG Import (server-side, no AJAX) - Now supports WooCommerce & Algolytics COG */
        add_action( 'admin_post_spvs_import_cog', array( $this, 'import_cog_costs' ) );

        /** Bulk historical profit recalculation */
        add_action( 'admin_post_spvs_recalc_historical_profit', array( $this, 'recalculate_historical_profit' ) );

        // AJAX actions for batch processing
        add_action( 'wp_ajax_spvs_get_recalc_count', array( $this, 'ajax_get_recalc_count' ) );
        add_action( 'wp_ajax_spvs_recalc_batch', array( $this, 'ajax_recalc_batch' ) );

        /** Daily cron for inventory totals */
        add_action( 'init', array( $this, 'maybe_schedule_daily_cron' ) );
        add_action( 'spvs_daily_inventory_recalc', array( $this, 'recalculate_inventory_totals' ) );
        add_action( 'spvs_daily_inventory_recalc', array( $this, 'cleanup_old_audit_logs' ) );

        /** Dedicated admin pages under WooCommerce */
        add_action( 'admin_menu', array( $this, 'register_admin_pages' ) );

        /** Enqueue admin scripts and styles */
        add_action( 'admin_enqueue_scripts', array( $this, 'enqueue_admin_assets' ) );
    }

    /** ---------------- Admin assets ---------------- */
    public function enqueue_admin_assets( $hook ) {
        if ( 'woocommerce_page_spvs-dashboard' === $hook ) {
            // Enqueue Chart.js for visualizations
            wp_enqueue_script( 'chart-js', 'https://cdn.jsdelivr.net/npm/chart.js@3.9.1/dist/chart.min.js', array(), '3.9.1', true );

            // Add print styles for PDF export via browser
            wp_add_inline_style( 'wp-admin', '
                @media print {
                    .wrap > h1, .nav-tab-wrapper, form, .button, .notice, #wpadminbar, #adminmenumain, .update-nag {
                        display: none !important;
                    }
                    table.widefat {
                        border: 1px solid #000;
                        page-break-inside: auto;
                    }
                    table.widefat tr {
                        page-break-inside: avoid;
                        page-break-after: auto;
                    }
                    table.widefat thead {
                        display: table-header-group;
                    }
                    body {
                        font-size: 10pt;
                    }
                }
            ' );
        }
    }

    /** ---------------- Product admin ---------------- */
    public function add_product_cost_field() {
        global $thepostid;
        $pid = $thepostid ? $thepostid : get_the_ID();
        echo '<div class="options_group">';
        woocommerce_wp_text_input( array(
            'id'                => self::PRODUCT_COST_META,
            'label'             => esc_html__( 'Cost price', 'spvs-cost-profit' ),
            'desc_tip'          => true,
            'description'       => esc_html__( 'Your unit cost (ex tax) for this product/variation.', 'spvs-cost-profit' ),
            'type'              => 'number',
            'custom_attributes' => array( 'step' => '0.0001', 'min' => '0' ),
            'data_type'         => 'price',
            'value'             => wc_format_localized_price( $this->get_product_cost_raw( $pid ) ),
        ) );
        echo '</div>';
    }

    public function save_product_cost_field( $product ) {
        if ( ! $product instanceof WC_Product ) return;

        // Get old value for audit
        $old_value = $this->get_product_cost_raw( $product->get_id() );

        $raw = isset( $_POST[ self::PRODUCT_COST_META ] ) ? wp_unslash( $_POST[ self::PRODUCT_COST_META ] ) : '';
        $value = $raw !== '' ? wc_clean( $raw ) : '';
        $value = $value !== '' ? wc_format_decimal( $value, wc_get_price_decimals() ) : '';

        // Only update if value changed
        if ( $value !== $old_value ) {
            if ( $value === '' ) {
                $product->delete_meta_data( self::PRODUCT_COST_META );
                $this->log_cost_change( $product->get_id(), 'delete', $old_value, null, 'product_edit' );
            } else {
                $product->update_meta_data( self::PRODUCT_COST_META, $value );
                $action = $old_value === '' ? 'create' : 'update';
                $this->log_cost_change( $product->get_id(), $action, $old_value, $value, 'product_edit' );
            }
            $product->save();
        }
    }

    private function get_product_cost_raw( $product_id ) {
        $value = get_post_meta( $product_id, self::PRODUCT_COST_META, true );
        return $value !== '' ? $value : '';
    }

    private function get_product_cost( $product_id ) {
        // Returns a float, falling back from variation → parent if needed.
        $value = $this->get_product_cost_raw( $product_id );
        if ( $value === '' ) {
            $product = function_exists( 'wc_get_product' ) ? wc_get_product( $product_id ) : null;
            if ( $product && $product->is_type( 'variation' ) ) {
                $parent_id = $product->get_parent_id();
                if ( $parent_id ) {
                    $value = $this->get_product_cost_raw( $parent_id );
                }
            }
        }
        return $value !== '' ? (float) $value : 0.0;
    }

    /** --------------- Variations --------------- */
    public function add_variation_cost_field( $loop, $variation_data, $variation ) {
        $variation_id = is_object( $variation ) && isset( $variation->ID ) ? $variation->ID : (int) $variation;
        $value = $this->get_product_cost_raw( $variation_id );
        $value = $value !== '' ? wc_format_localized_price( $value ) : '';
        echo '<div class="form-row form-row-full">';
        woocommerce_wp_text_input( array(
            'id'                => self::PRODUCT_COST_META . '[' . $variation_id . ']',
            'label'             => esc_html__( 'Cost price', 'spvs-cost-profit' ),
            'desc_tip'          => true,
            'description'       => esc_html__( 'Your unit cost (ex tax) for this variation.', 'spvs-cost-profit' ),
            'type'              => 'number',
            'custom_attributes' => array( 'step' => '0.0001', 'min' => '0' ),
            'data_type'         => 'price',
            'value'             => $value,
        ) );
        echo '</div>';
    }

    public function save_variation_cost_field( $variation_id, $i ) {
        if ( isset( $_POST[ self::PRODUCT_COST_META ][ $variation_id ] ) ) {
            // Get old value for audit
            $old_value = $this->get_product_cost_raw( $variation_id );

            $raw = wp_unslash( $_POST[ self::PRODUCT_COST_META ][ $variation_id ] );
            $value = $raw !== '' ? wc_clean( $raw ) : '';
            $value = $value !== '' ? wc_format_decimal( $value, wc_get_price_decimals() ) : '';

            // Only update if value changed
            if ( $value !== $old_value ) {
                if ( $value === '' ) {
                    delete_post_meta( $variation_id, self::PRODUCT_COST_META );
                    $this->log_cost_change( $variation_id, 'delete', $old_value, null, 'variation_edit' );
                } else {
                    update_post_meta( $variation_id, self::PRODUCT_COST_META, $value );
                    $action = $old_value === '' ? 'create' : 'update';
                    $this->log_cost_change( $variation_id, $action, $old_value, $value, 'variation_edit' );
                }
            }
        }
    }

    /** --------------- Quick Edit --------------- */
    public function add_cost_to_product_column_data( $column, $post_id ) {
        // Add cost data to product list for Quick Edit to pick up via JavaScript
        if ( 'name' === $column ) {
            $cost = $this->get_product_cost_raw( $post_id );
            echo '<div class="hidden spvs-cost-inline" data-cost="' . esc_attr( $cost ) . '"></div>';
        }
    }

    public function add_quick_edit_cost_field() {
        ?>
        <br class="clear" />
        <label class="alignleft">
            <span class="title"><?php esc_html_e( 'Cost Price', 'spvs-cost-profit' ); ?></span>
            <span class="input-text-wrap">
                <input type="number" step="0.0001" min="0" name="<?php echo esc_attr( self::PRODUCT_COST_META ); ?>" class="text wc_input_price" placeholder="<?php esc_attr_e( 'Cost', 'spvs-cost-profit' ); ?>" value="">
            </span>
        </label>
        <script type="text/javascript">
        jQuery(function($) {
            $('#the-list').on('click', '.editinline', function() {
                var post_id = $(this).closest('tr').attr('id').replace('post-', '');
                var cost = $('#post-' + post_id).find('.spvs-cost-inline').data('cost');
                $('input[name="<?php echo esc_js( self::PRODUCT_COST_META ); ?>"]').val(cost || '');
            });
        });
        </script>
        <?php
    }

    public function save_quick_edit_cost_field( $product ) {
        if ( ! $product instanceof WC_Product ) return;
        if ( isset( $_REQUEST[ self::PRODUCT_COST_META ] ) ) {
            // Get old value for audit
            $old_value = $this->get_product_cost_raw( $product->get_id() );

            $raw = wp_unslash( $_REQUEST[ self::PRODUCT_COST_META ] );
            $value = $raw !== '' ? wc_clean( $raw ) : '';
            $value = $value !== '' ? wc_format_decimal( $value, wc_get_price_decimals() ) : '';

            // Only update if value changed
            if ( $value !== $old_value ) {
                if ( $value === '' ) {
                    $product->delete_meta_data( self::PRODUCT_COST_META );
                    $this->log_cost_change( $product->get_id(), 'delete', $old_value, null, 'quick_edit' );
                } else {
                    $product->update_meta_data( self::PRODUCT_COST_META, $value );
                    $action = $old_value === '' ? 'create' : 'update';
                    $this->log_cost_change( $product->get_id(), $action, $old_value, $value, 'quick_edit' );
                }
            }
        }
    }

    /** --------------- Bulk Edit --------------- */
    public function add_bulk_edit_cost_field() {
        ?>
        <br class="clear" />
        <label class="alignleft">
            <span class="title"><?php esc_html_e( 'Cost Price', 'spvs-cost-profit' ); ?></span>
            <span class="input-text-wrap">
                <select name="<?php echo esc_attr( self::PRODUCT_COST_META ); ?>_change" class="change_to">
                    <option value=""><?php esc_html_e( '— No change —', 'spvs-cost-profit' ); ?></option>
                    <option value="set"><?php esc_html_e( 'Set to:', 'spvs-cost-profit' ); ?></option>
                    <option value="increase"><?php esc_html_e( 'Increase by (fixed):', 'spvs-cost-profit' ); ?></option>
                    <option value="decrease"><?php esc_html_e( 'Decrease by (fixed):', 'spvs-cost-profit' ); ?></option>
                    <option value="increase_percent"><?php esc_html_e( 'Increase by (%):', 'spvs-cost-profit' ); ?></option>
                    <option value="decrease_percent"><?php esc_html_e( 'Decrease by (%):', 'spvs-cost-profit' ); ?></option>
                </select>
            </span>
        </label>
        <label class="alignleft">
            <span class="title">&nbsp;</span>
            <span class="input-text-wrap">
                <input type="number" step="0.0001" min="0" name="<?php echo esc_attr( self::PRODUCT_COST_META ); ?>_value" class="text wc_input_price" placeholder="<?php esc_attr_e( 'Value', 'spvs-cost-profit' ); ?>" value="">
            </span>
        </label>
        <?php
    }

    public function save_bulk_edit_cost_field( $product ) {
        if ( ! $product instanceof WC_Product ) return;

        $change_type = isset( $_REQUEST[ self::PRODUCT_COST_META . '_change' ] ) ? wc_clean( wp_unslash( $_REQUEST[ self::PRODUCT_COST_META . '_change' ] ) ) : '';
        $change_value = isset( $_REQUEST[ self::PRODUCT_COST_META . '_value' ] ) ? wc_clean( wp_unslash( $_REQUEST[ self::PRODUCT_COST_META . '_value' ] ) ) : '';

        if ( empty( $change_type ) || $change_value === '' ) {
            return;
        }

        $old_value = $this->get_product_cost_raw( $product->get_id() );
        $current_cost = (float) $old_value;
        $new_cost = $current_cost;

        switch ( $change_type ) {
            case 'set':
                $new_cost = (float) $change_value;
                break;
            case 'increase':
                $new_cost = $current_cost + (float) $change_value;
                break;
            case 'decrease':
                $new_cost = max( 0, $current_cost - (float) $change_value );
                break;
            case 'increase_percent':
                $new_cost = $current_cost * ( 1 + ( (float) $change_value / 100 ) );
                break;
            case 'decrease_percent':
                $new_cost = $current_cost * ( 1 - ( (float) $change_value / 100 ) );
                $new_cost = max( 0, $new_cost );
                break;
        }

        // Validate and format new cost
        $new_cost_formatted = wc_format_decimal( $new_cost, wc_get_price_decimals() );

        // Only update if value changed
        if ( $new_cost_formatted !== $old_value ) {
            $metadata = array(
                'change_type'  => $change_type,
                'change_value' => $change_value,
            );

            if ( $new_cost > 0 ) {
                $product->update_meta_data( self::PRODUCT_COST_META, $new_cost_formatted );
                $action = $old_value === '' ? 'create' : 'update';
                $this->log_cost_change( $product->get_id(), $action, $old_value, $new_cost_formatted, 'bulk_edit', $metadata );
            } else {
                $product->delete_meta_data( self::PRODUCT_COST_META );
                $this->log_cost_change( $product->get_id(), 'delete', $old_value, null, 'bulk_edit', $metadata );
            }
        }
    }

    /** --------------- Profit on orders --------------- */
    public function add_line_item_profit_on_checkout( $item, $cart_item_key, $values, $order ) {
        if ( ! $item instanceof WC_Order_Item_Product ) return;
        $product = $item->get_product();
        $qty = max( 0, (int) $item->get_quantity() );
        $line_total_ex_tax = (float) $item->get_total();
        $unit_cost = 0.0;
        if ( $product ) { $unit_cost = (float) $this->get_product_cost( $product->get_id() ); }
        $line_cost_total = $unit_cost * $qty;
        $line_profit     = $line_total_ex_tax - $line_cost_total;
        $item->add_meta_data( '_spvs_unit_cost', wc_format_decimal( $unit_cost, wc_get_price_decimals() ), false );
        $item->add_meta_data( self::ORDER_LINE_PROFIT_META, wc_format_decimal( $line_profit, wc_get_price_decimals() ), true );
    }

    public function recalculate_order_total_profit_by_id( $order_id, $refund_id ) {
        $order = wc_get_order( $order_id );
        if ( $order ) { $this->recalculate_order_total_profit( $order ); }
    }

    public function recalculate_order_total_profit( $order ) {
        if ( is_numeric( $order ) ) { $order = wc_get_order( $order ); }
        if ( ! $order instanceof WC_Order ) return;

        $total_profit = 0.0;
        foreach ( $order->get_items( 'line_item' ) as $item_id => $item ) {
            $qty = max( 0, (int) $item->get_quantity() );
            $line_total_ex_tax = (float) $item->get_total();
            $stored_profit = $item->get_meta( self::ORDER_LINE_PROFIT_META, true );
            if ( $stored_profit !== '' ) { $total_profit += (float) $stored_profit; continue; }
            $product = $item->get_product();
            $unit_cost = 0.0;
            if ( $product ) { $unit_cost = (float) $this->get_product_cost( $product->get_id() ); }
            $line_cost_total = $unit_cost * $qty;
            $total_profit   += ( $line_total_ex_tax - $line_cost_total );
        }
        $order->update_meta_data( self::ORDER_TOTAL_PROFIT_META, wc_format_decimal( $total_profit, wc_get_price_decimals() ) );
        $order->save_meta_data();
    }

    /** --------------- Order UI --------------- */
    public function add_profit_metabox() {
        $screen = function_exists( 'wc_get_page_screen_id' ) ? wc_get_page_screen_id( 'shop-order' ) : 'shop_order';
        add_meta_box( 'spvs_order_profit_box', esc_html__( 'Profit (ex tax)', 'spvs-cost-profit' ), array( $this, 'render_profit_metabox' ), $screen, 'side', 'default' );
    }

    public function render_profit_metabox( $post_or_screen ) {
        $order = wc_get_order( get_the_ID() );
        if ( ! $order ) { echo esc_html__( 'Order not found.', 'spvs-cost-profit' ); return; }
        $profit = get_post_meta( $order->get_id(), self::ORDER_TOTAL_PROFIT_META, true );
        if ( $profit === '' ) { $this->recalculate_order_total_profit( $order ); $profit = get_post_meta( $order->get_id(), self::ORDER_TOTAL_PROFIT_META, true ); }
        echo '<p><strong>' . esc_html__( 'Total Profit', 'spvs-cost-profit' ) . ':</strong> ' . wp_kses_post( wc_price( (float) $profit ) ) . '</p>';
        echo '<p class="description">' . esc_html__( 'Profit = line totals (ex tax) − unit cost × qty (per item); refunds are reflected in line totals.', 'spvs-cost-profit' ) . '</p>';
    }

    public function add_orders_list_profit_column_legacy( $columns ) {
        if ( isset( $columns['order_total'] ) ) {
            $new = array();
            foreach ( $columns as $key => $label ) {
                $new[ $key ] = $label;
                if ( 'order_total' === $key ) { $new['spvs_profit'] = esc_html__( 'Profit', 'spvs-cost-profit' ); }
            }
            return $new;
        }
        $columns['spvs_profit'] = esc_html__( 'Profit', 'spvs-cost-profit' );
        return $columns;
    }

    public function render_orders_list_profit_column_legacy( $column, $post_id ) {
        if ( 'spvs_profit' !== $column ) return;
        $profit = get_post_meta( $post_id, self::ORDER_TOTAL_PROFIT_META, true );
        if ( $profit === '' ) { $order = wc_get_order( $post_id ); if ( $order ) { $this->recalculate_order_total_profit( $order ); $profit = get_post_meta( $post_id, self::ORDER_TOTAL_PROFIT_META, true ); } }
        echo wp_kses_post( wc_price( (float) $profit ) );
    }

    public function add_orders_list_profit_column_hpos( $columns ) { $columns['spvs_profit'] = esc_html__( 'Profit', 'spvs-cost-profit' ); return $columns; }

    public function render_orders_list_profit_column_hpos( $column, $order ) {
        if ( 'spvs_profit' !== $column ) return;
        $order_id = is_object( $order ) && method_exists( $order, 'get_id' ) ? $order->get_id() : 0;
        $profit = $order_id ? get_post_meta( $order_id, self::ORDER_TOTAL_PROFIT_META, true ) : '';
        if ( $profit === '' && $order_id ) { $this->recalculate_order_total_profit( $order ); $profit = get_post_meta( $order_id, self::ORDER_TOTAL_PROFIT_META, true ); }
        echo wp_kses_post( wc_price( (float) $profit ) );
    }

    public function add_orders_list_profit_column_shop_table( $columns ) { $columns['spvs_profit'] = esc_html__( 'Profit', 'spvs-cost-profit' ); return $columns; }

    public function render_orders_list_profit_column_shop_table( $column, $order ) {
        if ( 'spvs_profit' !== $column ) return;
        if ( is_numeric( $order ) ) { $order = wc_get_order( $order ); }
        if ( ! $order instanceof WC_Order ) return;
        $order_id = $order->get_id();
        $profit = get_post_meta( $order_id, self::ORDER_TOTAL_PROFIT_META, true );
        if ( $profit === '' ) { $this->recalculate_order_total_profit( $order ); $profit = get_post_meta( $order->get_id(), self::ORDER_TOTAL_PROFIT_META, true ); }
        echo wp_kses_post( wc_price( (float) $profit ) );
    }

    public function make_profit_column_sortable( $columns ) { $columns['spvs_profit'] = 'spvs_profit'; return $columns; }
    public function orders_list_sort_by_profit_query( $query ) {
        if ( ! is_admin() || ! $query->is_main_query() ) return;
        if ( 'spvs_profit' === $query->get( 'orderby' ) ) { $query->set( 'meta_key', self::ORDER_TOTAL_PROFIT_META ); $query->set( 'orderby', 'meta_value_num' ); }
    }

    /** --------------- TCOP bar --------------- */
    public function maybe_render_tcop_bar() {
        $is_orders_screen = ( isset( $_GET['page'] ) && 'wc-orders' === $_GET['page'] ) || ( isset( $GLOBALS['typenow'] ) && 'shop_order' === $GLOBALS['typenow'] );
        if ( ! is_admin() || ! $is_orders_screen ) return;

        $totals = get_option( self::INVENTORY_TOTALS_OPTION, array() );
        $tcop   = isset( $totals['tcop'] ) ? (float) $totals['tcop'] : 0.0;
        $retail = isset( $totals['retail'] ) ? (float) $totals['retail'] : 0.0;
        $updated = isset( $totals['updated'] ) ? (int) $totals['updated'] : 0;

        $nonce = wp_create_nonce( 'spvs_recalc_inventory' );
        $action_url = admin_url( 'admin-post.php?action=spvs_recalc_inventory&_wpnonce=' . $nonce );

        echo '<div class="notice notice-info spvs-tcop-bar" style="margin:12px 20px 0; padding:10px 12px; display:flex; flex-wrap:wrap; align-items:center; gap:12px;">';
        echo '<strong>TCOP:</strong> <span>' . wp_kses_post( wc_price( $tcop ) ) . '</span>';
        echo '<span style="margin-left:16px;"><strong>Retail:</strong> ' . wp_kses_post( wc_price( $retail ) ) . '</span>';
        if ( $retail > 0 ) { $margin = $retail - $tcop; echo '<span style="margin-left:16px;"><strong>Spread:</strong> ' . wp_kses_post( wc_price( $margin ) ) . '</span>'; }
        if ( $updated ) { echo '<span style="opacity:0.7; margin-left:16px;">' . esc_html__( 'Updated', 'spvs-cost-profit' ) . ' ' . esc_html( human_time_diff( $updated, time() ) ) . ' ' . esc_html__( 'ago', 'spvs-cost-profit' ) . '</span>'; }
        echo '<a href="' . esc_url( $action_url ) . '" class="button button-primary" style="margin-left:auto;">' . esc_html__( 'Recalculate', 'spvs-cost-profit' ) . '</a>';
        echo '</div>';
    }

    /** --------------- Inventory totals calc --------------- */
    public function maybe_schedule_daily_cron() {
        if ( ! wp_next_scheduled( 'spvs_daily_inventory_recalc' ) ) {
            $timestamp = strtotime( '02:30:00' );
            if ( ! $timestamp || $timestamp <= time() ) $timestamp = time() + HOUR_IN_SECONDS;
            wp_schedule_event( $timestamp, 'daily', 'spvs_daily_inventory_recalc' );
        }
    }

    public function handle_recalc_inventory() {
        if ( ! current_user_can( 'read' ) ) wp_die( esc_html__( 'Insufficient permissions.', 'spvs-cost-profit' ) );
        check_admin_referer( 'spvs_recalc_inventory' );
        $this->recalculate_inventory_totals();
        $redirect = wp_get_referer() ? wp_get_referer() : admin_url( 'admin.php?page=wc-orders' );
        wp_safe_redirect( $redirect ); exit;
    }

    public function recalculate_inventory_totals() {
        if ( get_transient( self::RECALC_LOCK_TRANSIENT ) ) return;
        set_transient( self::RECALC_LOCK_TRANSIENT, 1, MINUTE_IN_SECONDS );

        $batch_size = 250; $paged = 1;
        $tcop_total = 0.0; $retail_total = 0.0;
        $processed = 0; $managed = 0; $qty_gt0 = 0;

        while ( true ) {
            $q = new WP_Query( array(
                'post_type'      => array( 'product', 'product_variation' ),
                'post_status'    => 'publish',
                'posts_per_page' => $batch_size,
                'paged'          => $paged,
                'fields'         => 'ids',
                'no_found_rows'  => true,
            ) );
            if ( ! $q->have_posts() ) break;

            foreach ( $q->posts as $pid ) {
                $product = wc_get_product( $pid ); if ( ! $product ) continue;
                $processed++;

                // Only count products with stock management enabled AND stock status = 'instock'
                $is_in_stock = $product->get_stock_status() === 'instock';
                $is_managing_stock = $product->managing_stock();
                $qty = ( $is_managing_stock && $is_in_stock ) ? (int) $product->get_stock_quantity() : 0;

                if ( $is_managing_stock ) $managed++;
                if ( $qty > 0 ) $qty_gt0++;

                if ( $qty <= 0 ) { delete_post_meta( $pid, self::PRODUCT_COST_TOTAL_META ); delete_post_meta( $pid, self::PRODUCT_RETAIL_TOTAL_META ); continue; }

                $unit_cost = (float) $this->get_product_cost( $pid );
                $reg_price = (float) $product->get_regular_price();
                $line_cost   = $unit_cost * $qty;
                $line_retail = $reg_price * $qty;

                update_post_meta( $pid, self::PRODUCT_COST_TOTAL_META, wc_format_decimal( $line_cost, wc_get_price_decimals() ) );
                update_post_meta( $pid, self::PRODUCT_RETAIL_TOTAL_META, wc_format_decimal( $line_retail, wc_get_price_decimals() ) );

                $tcop_total   += $line_cost;
                $retail_total += $line_retail;
            }

            $paged++; usleep(150000);
        }

        update_option( self::INVENTORY_TOTALS_OPTION, array(
            'tcop'    => wc_format_decimal( $tcop_total, wc_get_price_decimals() ),
            'retail'  => wc_format_decimal( $retail_total, wc_get_price_decimals() ),
            'count'   => (int) $processed,
            'managed' => (int) $managed,
            'qty_gt0' => (int) $qty_gt0,
            'updated' => time(),
        ), false );
    }

    /** ---------------- COG Import (Server-side, no AJAX) ---------------- */
    public function import_cog_costs() {
        if ( ! current_user_can( 'manage_woocommerce' ) ) wp_die( esc_html__( 'Insufficient permissions.', 'spvs-cost-profit' ) );
        check_admin_referer( 'spvs_import_cog' );

        global $wpdb;

        $overwrite = isset( $_POST['spvs_cog_overwrite'] ) && $_POST['spvs_cog_overwrite'] === '1';
        $delete_after = isset( $_POST['spvs_cog_delete_after'] ) && $_POST['spvs_cog_delete_after'] === '1';

        // Support multiple COG plugin formats
        $cog_meta_keys = array( '_wc_cog_cost', '_alg_wc_cog_cost' );

        $imported = 0;
        $updated = 0;
        $skipped = 0;

        foreach ( $cog_meta_keys as $cog_key ) {
            // Get all product IDs with this COG format
            $product_ids = $wpdb->get_col( $wpdb->prepare( "
                SELECT DISTINCT pm.post_id
                FROM {$wpdb->postmeta} pm
                INNER JOIN {$wpdb->posts} p ON pm.post_id = p.ID
                WHERE pm.meta_key = %s
                AND pm.meta_value != ''
                AND pm.meta_value != '0'
                AND p.post_type IN ('product', 'product_variation')
                ORDER BY pm.post_id ASC
            ", $cog_key ) );

            foreach ( $product_ids as $product_id ) {
                $cog_cost = get_post_meta( $product_id, $cog_key, true );

            // CRITICAL: Verify COG cost is valid before doing ANYTHING
            if ( empty( $cog_cost ) || floatval( $cog_cost ) <= 0 ) {
                $skipped++;
                continue;
            }

            $existing_cost = get_post_meta( $product_id, self::PRODUCT_COST_META, true );

            // Skip if already has cost and not overwriting
            if ( ! empty( $existing_cost ) && floatval( $existing_cost ) > 0 && ! $overwrite ) {
                $skipped++;
                continue;
            }

            // ONLY update if we have valid COG cost
            $new_cost = wc_format_decimal( $cog_cost );
            update_post_meta( $product_id, self::PRODUCT_COST_META, $new_cost );

            $action = 'import';
            if ( ! empty( $existing_cost ) && floatval( $existing_cost ) > 0 ) {
                $updated++;
                $action = 'update';
            } else {
                $imported++;
                $action = 'create';
            }

                // Log the change
                $this->log_cost_change( $product_id, $action, $existing_cost, $new_cost, 'cog_import', array( 'source' => $cog_key, 'overwrite' => $overwrite, 'delete_after' => $delete_after ) );

                // ONLY delete COG data if successfully imported
                if ( $delete_after ) {
                    delete_post_meta( $product_id, $cog_key );
                }

                // Small delay every 100 products to avoid timeout
                if ( ( $imported + $updated + $skipped ) % 100 === 0 ) {
                    usleep( 100000 );
                }
            }
        }

        $msg = sprintf( 'cog_import_done:%d:%d:%d', $imported, $updated, $skipped );
        wp_safe_redirect( add_query_arg( array( 'page' => 'spvs-dashboard', 'tab' => 'import', 'spvs_msg' => rawurlencode( $msg ) ), admin_url( 'admin.php' ) ) );
        exit;
    }

    /** ---------------- CSV Import helpers ---------------- */
    private function spvs_resolve_product_from_row( $row ) {
        $pid = 0; $product = null;

        // 1) By explicit ID (product_id / id / variation_id)
        foreach ( array( 'product_id', 'id', 'variation_id' ) as $k ) {
            if ( isset( $row[ $k ] ) && $row[ $k ] !== '' ) {
                $pid = absint( $row[ $k ] );
                break;
            }
        }
        if ( $pid ) {
            $product = wc_get_product( $pid );
            if ( $product ) { return $product; }
        }

        // 2) By SKU
        if ( isset( $row['sku'] ) && $row['sku'] !== '' ) {
            $ids = wc_get_products( array( 'sku' => sanitize_text_field( $row['sku'] ), 'return' => 'ids', 'limit' => 1 ) );
            if ( ! empty( $ids ) ) {
                $product = wc_get_product( $ids[0] );
                if ( $product ) { return $product; }
            }
        }

        // 3) By slug (post_name) — parent products only
        if ( isset( $row['slug'] ) && $row['slug'] !== '' ) {
            $post = get_page_by_path( sanitize_title( $row['slug'] ), OBJECT, 'product' );
            if ( $post && isset( $post->ID ) ) {
                $product = wc_get_product( $post->ID );
                if ( $product ) { return $product; }
            }
        }

        return $product;
    }

    public function download_cost_template_csv() {
        if ( ! current_user_can( 'read' ) ) wp_die( esc_html__( 'Insufficient permissions.', 'spvs-cost-profit' ) );
        $filename = 'spvs-costs-template.csv';
        header( 'Content-Type: text/csv; charset=utf-8' );
        header( 'Content-Disposition: attachment; filename=' . $filename );
        $out = fopen( 'php://output', 'w' );
        fputcsv( $out, array( 'sku', 'product_id', 'cost' ) );
        fclose( $out ); exit;
    }

    public function download_cost_import_misses() {
        if ( ! current_user_can( 'manage_woocommerce' ) ) wp_die( esc_html__( 'Insufficient permissions.', 'spvs-cost-profit' ) );
        $miss = get_transient( self::IMPORT_MISSES_TRANSIENT );
        if ( ! is_array( $miss ) || empty( $miss ) ) {
            wp_die( esc_html__( 'No unmatched rows available from the last import.', 'spvs-cost-profit' ) );
        }
        header( 'Content-Type: text/csv; charset=utf-8' );
        header( 'Content-Disposition: attachment; filename=spvs-cost-import-misses.csv' );
        $out = fopen( 'php://output', 'w' );
        $header = array_keys( $miss[0] );
        fputcsv( $out, $header );
        foreach ( $miss as $row ) {
            $line = array();
            foreach ( $header as $k ) { $line[] = isset( $row[ $k ] ) ? $row[ $k ] : ''; }
            fputcsv( $out, $line );
        }
        fclose( $out );
        delete_transient( self::IMPORT_MISSES_TRANSIENT );
        exit;
    }

    public function import_costs_csv() {
        if ( ! current_user_can( 'manage_woocommerce' ) ) wp_die( esc_html__( 'You do not have permission to import costs.', 'spvs-cost-profit' ) );
        check_admin_referer( 'spvs_import_costs_csv' );

        if ( empty( $_FILES['spvs_costs_file']['tmp_name'] ) ) { wp_safe_redirect( add_query_arg( array( 'page' => 'spvs-dashboard', 'tab' => 'import', 'spvs_msg' => 'no_file' ), admin_url( 'admin.php' ) ) ); exit; }
        $tmp = $_FILES['spvs_costs_file']['tmp_name'];
        $fh = fopen( $tmp, 'r' );
        if ( ! $fh ) { wp_safe_redirect( add_query_arg( array( 'page' => 'spvs-dashboard', 'tab' => 'import', 'spvs_msg' => 'open_fail' ), admin_url( 'admin.php' ) ) ); exit; }

        $header = fgetcsv( $fh ); if ( ! is_array( $header ) ) { $header = array(); }
        $header = array_map( 'sanitize_key', $header );
        if ( ! in_array( 'cost', $header, true ) ) { fclose( $fh ); wp_safe_redirect( add_query_arg( array( 'page' => 'spvs-dashboard', 'tab' => 'import', 'spvs_msg' => 'missing_cost_col' ), admin_url( 'admin.php' ) ) ); exit; }

        $updated = 0; $skipped = 0; $errors = 0; $total = 0; $misses = array();
        while ( ( $row = fgetcsv( $fh ) ) !== false ) {
            $total++; $assoc = array();
            foreach ( $header as $i => $key ) { $assoc[ $key ] = isset( $row[ $i ] ) ? trim( (string) $row[ $i ] ) : ''; }

            $product = $this->spvs_resolve_product_from_row( $assoc );
            if ( ! $product ) { $skipped++; $misses[] = $assoc; continue; }

            $raw_cost = isset( $assoc['cost'] ) ? $assoc['cost'] : '';
            if ( $raw_cost === '' ) { $skipped++; continue; }

            $value = wc_format_decimal( wc_clean( $raw_cost ), wc_get_price_decimals() );
            if ( $value === '' ) { $skipped++; continue; }

            // Get old value for audit
            $old_value = $this->get_product_cost_raw( $product->get_id() );

            // Only update if value changed
            if ( $value !== $old_value ) {
                $ok = update_post_meta( $product->get_id(), self::PRODUCT_COST_META, $value );
                if ( false === $ok ) {
                    $errors++;
                } else {
                    $updated++;
                    $action = $old_value === '' ? 'create' : 'update';
                    $this->log_cost_change( $product->get_id(), $action, $old_value, $value, 'csv_import', array( 'row' => $total ) );
                }
            } else {
                $skipped++; // Value hasn't changed
            }

            if ( $updated % 200 == 0 ) { usleep(200000); }
        }
        fclose( $fh );

        if ( ! empty( $misses ) ) { set_transient( self::IMPORT_MISSES_TRANSIENT, $misses, HOUR_IN_SECONDS ); }

        $recalc = isset( $_POST['spvs_recalc_after'] ) && $_POST['spvs_recalc_after'] === '1';
        if ( $recalc ) { $this->recalculate_inventory_totals(); }

        $msg = sprintf( 'import_done:%d:%d:%d:%d', $total, $updated, $skipped, $errors );
        wp_safe_redirect( add_query_arg( array( 'page' => 'spvs-dashboard', 'tab' => 'import', 'spvs_msg' => rawurlencode( $msg ) ), admin_url( 'admin.php' ) ) ); exit;
    }

    /** ---------------- Column helpers for CSV/Preview ---------------- */
    private function spvs_get_available_columns() {
        $cols = array(
            'product_id'        => 'Product ID',
            'parent_id'         => 'Parent ID',
            'type'              => 'Type',
            'status'            => 'Status',
            'sku'               => 'SKU',
            'name'              => 'Name',
            'attributes'        => 'Attributes',
            'categories'        => 'Categories',
            'tags'              => 'Tags',
            'manage_stock'      => 'Manage stock',
            'stock_status'      => 'Stock status',
            'qty'               => 'Stock quantity',
            'backorders'        => 'Backorders',
            'cost'              => 'Cost',
            'line_cost_total'   => 'Cost × Qty',
            'regular_price'     => 'Regular price',
            'sale_price'        => 'Sale price',
            'price'             => 'Current price',
            'line_retail_total' => 'Regular × Qty',
            'tax_class'         => 'Tax class',
            'weight'            => 'Weight',
            'dimensions'        => 'Dimensions',
            'date_created'      => 'Date created',
            'date_modified'     => 'Date modified',
        );
        return apply_filters( 'spvs_inventory_available_columns', $cols );
    }

    private function spvs_build_row_for_columns( WC_Product $product, array $columns ) {
        $pid = $product->get_id();
        $qty = $product->managing_stock() ? (int) $product->get_stock_quantity() : 0;
        $cost = (float) $this->get_product_cost( $pid );
        $regular = (float) $product->get_regular_price();
        $current_price = (float) $product->get_price();
        $line_cost = $cost * max(0, $qty);
        $line_retail = $regular * max(0, $qty);

        $terms_to_csv = function( $taxonomy ) use ( $pid ) {
            if ( ! taxonomy_exists( $taxonomy ) ) return '';
            $terms = wp_get_post_terms( $pid, $taxonomy, array( 'fields' => 'names' ) );
            return is_wp_error( $terms ) ? '' : implode( ', ', $terms );
        };

        $attr_parts = array();
        $attributes = $product->get_attributes();
        if ( is_array( $attributes ) ) {
            foreach ( $attributes as $name => $attr ) {
                $label = is_string( $name ) ? wc_attribute_label( $name ) : (string) $name;
                $value = '';
                if ( is_object( $attr ) && method_exists( $attr, 'get_options' ) ) {
                    $opts = (array) $attr->get_options();
                    if ( method_exists( $attr, 'is_taxonomy' ) && $attr->is_taxonomy() ) {
                        $names = array();
                        foreach ( $opts as $term_id ) {
                            $t = get_term( (int) $term_id );
                            if ( $t && ! is_wp_error( $t ) ) $names[] = $t->name;
                        }
                        $value = implode( '/', $names );
                    } else {
                        $value = implode( '/', array_map( 'wc_clean', $opts ) );
                    }
                } else {
                    if ( is_scalar( $attr ) ) $value = (string) $attr;
                    elseif ( $product->is_type( 'variation' ) && is_string( $name ) ) $value = $product->get_attribute( $name );
                }
                $value = trim( (string) $value );
                if ( $value !== '' ) { $attr_parts[] = $label . ': ' . $value; }
            }
        }
        $attr_str = implode( ' | ', $attr_parts );

        $dims = trim( implode( ' × ', array_filter( array( $product->get_length(), $product->get_width(), $product->get_height() ) ) ) );

        $map = array(
            'product_id'        => $pid,
            'parent_id'         => $product->is_type('variation') ? $product->get_parent_id() : '',
            'type'              => $product->get_type(),
            'status'            => $product->get_status(),
            'sku'               => $product->get_sku(),
            'name'              => $product->get_formatted_name(),
            'attributes'        => $attr_str,
            'categories'        => $terms_to_csv( 'product_cat' ),
            'tags'              => $terms_to_csv( 'product_tag' ),
            'manage_stock'      => $product->managing_stock() ? 'yes' : 'no',
            'stock_status'      => $product->get_stock_status(),
            'qty'               => $qty,
            'backorders'        => $product->get_backorders(),
            'cost'              => $cost,
            'line_cost_total'   => $line_cost,
            'regular_price'     => $regular,
            'sale_price'        => (float) $product->get_sale_price(),
            'price'             => $current_price,
            'line_retail_total' => $line_retail,
            'tax_class'         => $product->get_tax_class(),
            'weight'            => $product->get_weight(),
            'dimensions'        => $dims,
            'date_created'      => $product->get_date_created() ? $product->get_date_created()->date_i18n( 'Y-m-d H:i' ) : '',
            'date_modified'     => $product->get_date_modified() ? $product->get_date_modified()->date_i18n( 'Y-m-d H:i' ) : '',
        );

        foreach ( $columns as $key ) { $map[ $key ] = apply_filters( 'spvs_inventory_csv_value_' . $key, isset( $map[ $key ] ) ? $map[ $key ] : '', $product, $pid ); }

        $row = array(); foreach ( $columns as $key ) { $row[] = isset( $map[ $key ] ) ? $map[ $key ] : ''; }
        return $row;
    }

    /** --------------- Profit reports with flexible grouping --------------- */
    private function get_profit_data_by_period( $start_date = null, $end_date = null, $grouping = 'monthly' ) {
        global $wpdb;

        // Default date range
        if ( ! $start_date ) {
            if ( 'daily' === $grouping ) {
                $start_date = date( 'Y-m-d', strtotime( '-30 days' ) );
            } elseif ( 'yearly' === $grouping ) {
                $start_date = date( 'Y-01-01', strtotime( '-4 years' ) );
            } else {
                $start_date = date( 'Y-m-01', strtotime( '-11 months' ) );
            }
        }
        if ( ! $end_date ) {
            $end_date = date( 'Y-m-d' );
        }

        // Set date format based on grouping
        $date_format = '%Y-%m'; // monthly default
        $group_label = 'period';
        if ( 'daily' === $grouping ) {
            $date_format = '%Y-%m-%d';
        } elseif ( 'yearly' === $grouping ) {
            $date_format = '%Y';
        }

        // Query orders with profit data
        $order_statuses = array_map( 'esc_sql', apply_filters( 'spvs_profit_report_order_statuses', array( 'wc-completed', 'wc-processing' ) ) );
        $status_list = "'" . implode( "','", $order_statuses ) . "'";

        // HPOS compatible query
        if ( function_exists( 'wc_get_container' ) ) {
            try {
                $orders_table = $wpdb->prefix . 'wc_orders';
                $orders_meta_table = $wpdb->prefix . 'wc_orders_meta';
                $order_items_table = $wpdb->prefix . 'woocommerce_order_items';
                $order_itemmeta_table = $wpdb->prefix . 'woocommerce_order_itemmeta';

                // Check if HPOS tables exist
                $table_exists = $wpdb->get_var( "SHOW TABLES LIKE '$orders_table'" );

                if ( $table_exists ) {
                    $query = $wpdb->prepare(
                        "SELECT
                            DATE_FORMAT(o.date_created_gmt, '$date_format') as period,
                            COUNT(DISTINCT o.id) as order_count,
                            SUM(CAST(om.meta_value AS DECIMAL(10,2))) as total_profit,
                            SUM(o.total_amount) as total_revenue
                        FROM {$orders_table} o
                        LEFT JOIN {$orders_meta_table} om ON o.id = om.order_id AND om.meta_key = %s
                        WHERE o.status IN ($status_list)
                        AND o.date_created_gmt >= %s
                        AND o.date_created_gmt <= %s
                        GROUP BY period
                        ORDER BY period ASC",
                        self::ORDER_TOTAL_PROFIT_META,
                        $start_date . ' 00:00:00',
                        $end_date . ' 23:59:59'
                    );

                    $results = $wpdb->get_results( $query );
                    if ( $results ) {
                        // Calculate total cost for each period
                        foreach ( $results as $row ) {
                            $row->total_cost = ( (float) $row->total_revenue ) - ( (float) $row->total_profit );
                        }
                        return $results;
                    }
                }
            } catch ( Exception $e ) {
                // Fall through to legacy query
            }
        }

        // Legacy post-based orders query
        $query = $wpdb->prepare(
            "SELECT
                DATE_FORMAT(p.post_date, '$date_format') as period,
                COUNT(DISTINCT p.ID) as order_count,
                SUM(CAST(pm.meta_value AS DECIMAL(10,2))) as total_profit,
                SUM(CAST(pm2.meta_value AS DECIMAL(10,2))) as total_revenue
            FROM {$wpdb->posts} p
            LEFT JOIN {$wpdb->postmeta} pm ON p.ID = pm.post_id AND pm.meta_key = %s
            LEFT JOIN {$wpdb->postmeta} pm2 ON p.ID = pm2.post_id AND pm2.meta_key = '_order_total'
            WHERE p.post_type = 'shop_order'
            AND p.post_status IN ($status_list)
            AND p.post_date >= %s
            AND p.post_date <= %s
            GROUP BY period
            ORDER BY period ASC",
            self::ORDER_TOTAL_PROFIT_META,
            $start_date . ' 00:00:00',
            $end_date . ' 23:59:59'
        );

        $results = $wpdb->get_results( $query );
        // Calculate total cost for each period
        foreach ( $results as $row ) {
            $row->total_cost = ( (float) $row->total_revenue ) - ( (float) $row->total_profit );
        }
        return $results;
    }

    public function export_profit_report_csv() {
        if ( ! current_user_can( 'read' ) ) wp_die( esc_html__( 'Insufficient permissions.', 'spvs-cost-profit' ) );
        check_admin_referer( 'spvs_export_profit_report' );

        $start_date = isset( $_GET['start_date'] ) ? sanitize_text_field( $_GET['start_date'] ) : '';
        $end_date = isset( $_GET['end_date'] ) ? sanitize_text_field( $_GET['end_date'] ) : '';
        $grouping = isset( $_GET['grouping'] ) ? sanitize_text_field( $_GET['grouping'] ) : 'monthly';

        $data = $this->get_profit_data_by_period( $start_date, $end_date, $grouping );

        $filename = 'profit-report-' . $grouping . '-' . date( 'Ymd-His' ) . '.csv';
        header( 'Content-Type: text/csv; charset=utf-8' );
        header( 'Content-Disposition: attachment; filename=' . $filename );

        $out = fopen( 'php://output', 'w' );
        fputcsv( $out, array( 'Period', 'Orders', 'Revenue', 'Cost', 'Profit', 'Margin %', 'Avg Profit/Order' ) );

        foreach ( $data as $row ) {
            $revenue = (float) $row->total_revenue;
            $profit = (float) $row->total_profit;
            $cost = (float) $row->total_cost;
            $orders = (int) $row->order_count;
            $margin = $revenue > 0 ? ( $profit / $revenue ) * 100 : 0;
            $avg_profit = $orders > 0 ? $profit / $orders : 0;

            fputcsv( $out, array(
                $row->period,
                $orders,
                number_format( $revenue, 2, '.', '' ),
                number_format( $cost, 2, '.', '' ),
                number_format( $profit, 2, '.', '' ),
                number_format( $margin, 2, '.', '' ),
                number_format( $avg_profit, 2, '.', '' ),
            ) );
        }

        fclose( $out );
        exit;
    }

    public function export_top_products_csv() {
        if ( ! current_user_can( 'read' ) ) wp_die( esc_html__( 'Insufficient permissions.', 'spvs-cost-profit' ) );
        check_admin_referer( 'spvs_export_top_products' );

        global $wpdb;

        $start_date = isset( $_GET['start_date'] ) ? sanitize_text_field( $_GET['start_date'] ) : date( 'Y-m-01' );
        $end_date = isset( $_GET['end_date'] ) ? sanitize_text_field( $_GET['end_date'] ) : date( 'Y-m-d' );
        $limit = isset( $_GET['limit'] ) ? absint( $_GET['limit'] ) : 50;
        if ( $limit < 1 || $limit > 500 ) $limit = 50;

        $order_statuses = array_map( 'esc_sql', array( 'wc-completed', 'wc-processing' ) );
        $status_list = "'" . implode( "','", $order_statuses ) . "'";

        // Try HPOS first
        $results = array();
        $orders_table = $wpdb->prefix . 'wc_orders';
        $table_exists = $wpdb->get_var( "SHOW TABLES LIKE '$orders_table'" );

        if ( $table_exists ) {
            $query = $wpdb->prepare(
                "SELECT
                    oim_product.meta_value as product_id,
                    SUM(oim_qty.meta_value) as total_qty,
                    SUM(oim_total.meta_value) as total_revenue,
                    SUM(oim_profit.meta_value) as total_profit
                FROM {$wpdb->prefix}woocommerce_order_items oi
                INNER JOIN {$wpdb->prefix}woocommerce_order_itemmeta oim_product
                    ON oi.order_item_id = oim_product.order_item_id AND oim_product.meta_key = '_product_id'
                LEFT JOIN {$wpdb->prefix}woocommerce_order_itemmeta oim_qty
                    ON oi.order_item_id = oim_qty.order_item_id AND oim_qty.meta_key = '_qty'
                LEFT JOIN {$wpdb->prefix}woocommerce_order_itemmeta oim_total
                    ON oi.order_item_id = oim_total.order_item_id AND oim_total.meta_key = '_line_total'
                LEFT JOIN {$wpdb->prefix}woocommerce_order_itemmeta oim_profit
                    ON oi.order_item_id = oim_profit.order_item_id AND oim_profit.meta_key = %s
                INNER JOIN {$orders_table} o ON oi.order_id = o.id
                WHERE o.status IN ($status_list)
                AND o.date_created_gmt >= %s AND o.date_created_gmt <= %s
                AND oi.order_item_type = 'line_item'
                GROUP BY product_id ORDER BY total_profit DESC LIMIT %d",
                self::ORDER_LINE_PROFIT_META,
                $start_date . ' 00:00:00',
                $end_date . ' 23:59:59',
                $limit
            );
            $results = $wpdb->get_results( $query );
        }

        if ( empty( $results ) ) {
            $query = $wpdb->prepare(
                "SELECT
                    oim_product.meta_value as product_id,
                    SUM(oim_qty.meta_value) as total_qty,
                    SUM(oim_total.meta_value) as total_revenue,
                    SUM(oim_profit.meta_value) as total_profit
                FROM {$wpdb->prefix}woocommerce_order_items oi
                INNER JOIN {$wpdb->prefix}woocommerce_order_itemmeta oim_product
                    ON oi.order_item_id = oim_product.order_item_id AND oim_product.meta_key = '_product_id'
                LEFT JOIN {$wpdb->prefix}woocommerce_order_itemmeta oim_qty
                    ON oi.order_item_id = oim_qty.order_item_id AND oim_qty.meta_key = '_qty'
                LEFT JOIN {$wpdb->prefix}woocommerce_order_itemmeta oim_total
                    ON oi.order_item_id = oim_total.order_item_id AND oim_total.meta_key = '_line_total'
                LEFT JOIN {$wpdb->prefix}woocommerce_order_itemmeta oim_profit
                    ON oi.order_item_id = oim_profit.order_item_id AND oim_profit.meta_key = %s
                INNER JOIN {$wpdb->posts} p ON oi.order_id = p.ID
                WHERE p.post_type = 'shop_order' AND p.post_status IN ($status_list)
                AND p.post_date >= %s AND p.post_date <= %s
                AND oi.order_item_type = 'line_item'
                GROUP BY product_id ORDER BY total_profit DESC LIMIT %d",
                self::ORDER_LINE_PROFIT_META,
                $start_date . ' 00:00:00',
                $end_date . ' 23:59:59',
                $limit
            );
            $results = $wpdb->get_results( $query );
        }

        $filename = 'top-products-' . date( 'Ymd-His' ) . '.csv';
        header( 'Content-Type: text/csv; charset=utf-8' );
        header( 'Content-Disposition: attachment; filename=' . $filename );

        $out = fopen( 'php://output', 'w' );
        fputcsv( $out, array( 'Rank', 'Product ID', 'Product Name', 'SKU', 'Qty Sold', 'Revenue', 'Profit', 'Margin %', 'Avg Profit/Unit' ) );

        $rank = 1;
        foreach ( $results as $row ) {
            $product = wc_get_product( $row->product_id );
            if ( ! $product ) continue;

            $qty = (int) $row->total_qty;
            $revenue = (float) $row->total_revenue;
            $profit = (float) $row->total_profit;
            $margin = $revenue > 0 ? ( $profit / $revenue ) * 100 : 0;
            $avg_profit = $qty > 0 ? $profit / $qty : 0;

            fputcsv( $out, array(
                $rank,
                $product->get_id(),
                $product->get_name(),
                $product->get_sku(),
                $qty,
                number_format( $revenue, 2, '.', '' ),
                number_format( $profit, 2, '.', '' ),
                number_format( $margin, 2, '.', '' ),
                number_format( $avg_profit, 2, '.', '' ),
            ) );

            $rank++;
        }

        fclose( $out );
        exit;
    }

    /** --------------- Admin pages --------------- */
    public function register_admin_pages() {
        add_submenu_page(
            'woocommerce',
            __( 'SPVS Dashboard', 'spvs-cost-profit' ),
            __( 'SPVS Dashboard', 'spvs-cost-profit' ),
            'read',
            'spvs-dashboard',
            array( $this, 'render_dashboard_page' )
        );
    }

    public function render_dashboard_page() {
        if ( ! current_user_can( 'read' ) ) wp_die( esc_html__( 'Insufficient permissions.', 'spvs-cost-profit' ) );

        // Get active tab
        $active_tab = isset( $_GET['tab'] ) ? sanitize_text_field( $_GET['tab'] ) : 'reports';

        echo '<div class="wrap">';
        echo '<h1>' . esc_html__( 'SPVS Cost & Profit Dashboard', 'spvs-cost-profit' ) . '</h1>';

        // Tab navigation
        $tabs = array(
            'reports'   => __( 'Profit Reports', 'spvs-cost-profit' ),
            'top-products' => __( 'Top Products', 'spvs-cost-profit' ),
            'inventory' => __( 'Inventory Value', 'spvs-cost-profit' ),
            'import'    => __( 'Import/Export', 'spvs-cost-profit' ),
            'health'    => __( 'Data Integrity', 'spvs-cost-profit' ),
        );

        echo '<h2 class="nav-tab-wrapper">';
        foreach ( $tabs as $tab_key => $tab_label ) {
            $active = ( $active_tab === $tab_key ) ? ' nav-tab-active' : '';
            $url = add_query_arg( array( 'page' => 'spvs-dashboard', 'tab' => $tab_key ), admin_url( 'admin.php' ) );
            echo '<a href="' . esc_url( $url ) . '" class="nav-tab' . esc_attr( $active ) . '">' . esc_html( $tab_label ) . '</a>';
        }
        echo '</h2>';

        // Render active tab content
        switch ( $active_tab ) {
            case 'top-products':
                $this->render_top_products_tab();
                break;
            case 'inventory':
                $this->render_inventory_tab();
                break;
            case 'import':
                $this->render_import_tab();
                break;
            case 'health':
                $this->render_health_tab();
                break;
            case 'reports':
            default:
                $this->render_reports_tab();
                break;
        }

        echo '</div>';
    }

    private function render_reports_tab() {
        // Get parameters
        $grouping = isset( $_GET['grouping'] ) ? sanitize_text_field( $_GET['grouping'] ) : 'monthly';
        if ( ! in_array( $grouping, array( 'daily', 'monthly', 'yearly' ), true ) ) {
            $grouping = 'monthly';
        }

        // Default date ranges based on grouping
        $default_start = '';
        $default_end = date( 'Y-m-d' );
        if ( 'daily' === $grouping ) {
            $default_start = date( 'Y-m-d', strtotime( '-30 days' ) );
        } elseif ( 'yearly' === $grouping ) {
            $default_start = date( 'Y-01-01', strtotime( '-4 years' ) );
        } else {
            $default_start = date( 'Y-m-01', strtotime( '-11 months' ) );
        }

        $start_date = isset( $_GET['start_date'] ) ? sanitize_text_field( $_GET['start_date'] ) : $default_start;
        $end_date = isset( $_GET['end_date'] ) ? sanitize_text_field( $_GET['end_date'] ) : $default_end;

        $report_data = $this->get_profit_data_by_period( $start_date, $end_date, $grouping );

        $export_url = add_query_arg( array(
            'action'     => 'spvs_export_profit_report',
            '_wpnonce'   => wp_create_nonce( 'spvs_export_profit_report' ),
            'start_date' => $start_date,
            'end_date'   => $end_date,
            'grouping'   => $grouping,
        ), admin_url( 'admin-post.php' ) );

        // Date shortcuts
        $this_month_start = date( 'Y-m-01' );
        $this_month_end = date( 'Y-m-t' );
        $last_month_start = date( 'Y-m-01', strtotime( 'first day of last month' ) );
        $last_month_end = date( 'Y-m-t', strtotime( 'last day of last month' ) );

        // Filter form
        echo '<div style="background: #fff; padding: 20px; margin: 20px 0; border: 1px solid #ccc;">';
        echo '<form method="get" id="spvs-report-form" style="display: flex; gap: 15px; flex-wrap: wrap; align-items: flex-end;">';
        echo '<input type="hidden" name="page" value="spvs-dashboard" />';
        echo '<input type="hidden" name="tab" value="reports" />';

        echo '<label><strong>' . esc_html__( 'Group By:', 'spvs-cost-profit' ) . '</strong><br/>';
        echo '<select name="grouping" style="min-width: 120px;">';
        echo '<option value="daily"' . selected( $grouping, 'daily', false ) . '>' . esc_html__( 'Daily', 'spvs-cost-profit' ) . '</option>';
        echo '<option value="monthly"' . selected( $grouping, 'monthly', false ) . '>' . esc_html__( 'Monthly', 'spvs-cost-profit' ) . '</option>';
        echo '<option value="yearly"' . selected( $grouping, 'yearly', false ) . '>' . esc_html__( 'Yearly', 'spvs-cost-profit' ) . '</option>';
        echo '</select></label>';

        echo '<label><strong>' . esc_html__( 'Start Date:', 'spvs-cost-profit' ) . '</strong><br/>';
        echo '<input type="date" name="start_date" id="spvs-start-date" value="' . esc_attr( $start_date ) . '" /></label>';

        echo '<label><strong>' . esc_html__( 'End Date:', 'spvs-cost-profit' ) . '</strong><br/>';
        echo '<input type="date" name="end_date" id="spvs-end-date" value="' . esc_attr( $end_date ) . '" /></label>';

        echo '<button class="button button-primary">' . esc_html__( 'Update Report', 'spvs-cost-profit' ) . '</button>';
        echo '<a class="button" href="' . esc_url( $export_url ) . '">' . esc_html__( 'Export CSV', 'spvs-cost-profit' ) . '</a>';
        echo '<button type="button" class="button" onclick="window.print();">' . esc_html__( 'Print / Save as PDF', 'spvs-cost-profit' ) . '</button>';
        echo '</form>';

        // Date shortcuts
        echo '<div style="margin-top: 10px; display: flex; gap: 8px;">';
        echo '<strong style="padding: 6px 0;">' . esc_html__( 'Quick Select:', 'spvs-cost-profit' ) . '</strong>';
        echo '<button type="button" class="button spvs-date-shortcut" data-start="' . esc_attr( $this_month_start ) . '" data-end="' . esc_attr( $this_month_end ) . '">' . esc_html__( 'This Month', 'spvs-cost-profit' ) . '</button>';
        echo '<button type="button" class="button spvs-date-shortcut" data-start="' . esc_attr( $last_month_start ) . '" data-end="' . esc_attr( $last_month_end ) . '">' . esc_html__( 'Last Month', 'spvs-cost-profit' ) . '</button>';
        echo '</div>';

        echo '<script>
        document.addEventListener("DOMContentLoaded", function() {
            document.querySelectorAll(".spvs-date-shortcut").forEach(function(btn) {
                btn.addEventListener("click", function() {
                    document.getElementById("spvs-start-date").value = this.dataset.start;
                    document.getElementById("spvs-end-date").value = this.dataset.end;
                    document.getElementById("spvs-report-form").submit();
                });
            });
        });
        </script>';

        echo '</div>';

        if ( empty( $report_data ) ) {
            echo '<div class="notice notice-warning"><p>';
            echo '<strong>' . esc_html__( 'No data found for the selected date range.', 'spvs-cost-profit' ) . '</strong><br>';
            echo esc_html( sprintf( __( 'Date range: %s to %s', 'spvs-cost-profit' ), $start_date, $end_date ) ) . '<br><br>';
            echo esc_html__( 'This could mean:', 'spvs-cost-profit' ) . '<br>';
            echo '• ' . esc_html__( 'No orders exist in this date range', 'spvs-cost-profit' ) . '<br>';
            echo '• ' . esc_html__( 'The date range is in the future', 'spvs-cost-profit' ) . '<br>';
            echo '• ' . esc_html__( 'Orders are in a different status (only completed/processing orders are shown)', 'spvs-cost-profit' ) . '<br>';
            echo '</p></div>';

            // Show sample of recent orders to help user understand date range
            global $wpdb;
            $sample_orders = $wpdb->get_results( "
                SELECT DATE(date_created_gmt) as order_date, COUNT(*) as count
                FROM {$wpdb->prefix}wc_orders
                WHERE status IN ('wc-completed', 'wc-processing')
                GROUP BY order_date
                ORDER BY order_date DESC
                LIMIT 5
            " );

            if ( ! empty( $sample_orders ) ) {
                echo '<div class="notice notice-info"><p>';
                echo '<strong>' . esc_html__( 'Recent order dates in your system:', 'spvs-cost-profit' ) . '</strong><br>';
                foreach ( $sample_orders as $sample ) {
                    echo esc_html( date_i18n( 'F j, Y', strtotime( $sample->order_date ) ) ) . ' (' . esc_html( $sample->count ) . ' ' . esc_html__( 'orders', 'spvs-cost-profit' ) . ')<br>';
                }
                echo '</p></div>';
            }
            return;
        }

        // Check for suspicious data (all profits are zero)
        $all_profits_zero = true;
        foreach ( $report_data as $row ) {
            if ( (float) $row->total_profit != 0 ) {
                $all_profits_zero = false;
                break;
            }
        }

        if ( $all_profits_zero ) {
            echo '<div class="notice notice-warning"><p>';
            echo esc_html__( 'Warning: All periods show $0 profit. This usually means:', 'spvs-cost-profit' ) . '<br>';
            echo '• ' . esc_html__( 'Product costs have not been set', 'spvs-cost-profit' ) . '<br>';
            echo '• ' . esc_html__( 'Historical profit data has not been calculated', 'spvs-cost-profit' ) . '<br>';
            echo '<br><strong>' . esc_html__( 'Action Required:', 'spvs-cost-profit' ) . '</strong><br>';
            echo '1. ' . sprintf( '<a href="%s">' . esc_html__( 'Import costs from COG plugin', 'spvs-cost-profit' ) . '</a>', esc_url( add_query_arg( array( 'page' => 'spvs-dashboard', 'tab' => 'import' ), admin_url( 'admin.php' ) ) ) ) . '<br>';
            echo '2. ' . sprintf( '<a href="%s">' . esc_html__( 'Recalculate historical profit', 'spvs-cost-profit' ) . '</a>', esc_url( add_query_arg( array( 'page' => 'spvs-dashboard', 'tab' => 'health' ), admin_url( 'admin.php' ) ) ) ) . '<br>';
            echo '</p></div>';
        }

        // Calculate totals
        $periods = array();
        $revenues = array();
        $costs = array();
        $profits = array();
        $total_revenue = 0;
        $total_cost = 0;
        $total_profit = 0;
        $total_orders = 0;

        foreach ( $report_data as $row ) {
            $periods[] = $row->period;
            $revenue = (float) $row->total_revenue;
            $cost = (float) $row->total_cost;
            $profit = (float) $row->total_profit;
            $revenues[] = $revenue;
            $costs[] = $cost;
            $profits[] = $profit;
            $total_revenue += $revenue;
            $total_cost += $cost;
            $total_profit += $profit;
            $total_orders += (int) $row->order_count;
        }

        $avg_margin = $total_revenue > 0 ? ( $total_profit / $total_revenue ) * 100 : 0;

        // Summary cards
        echo '<div style="display: flex; gap: 20px; margin: 20px 0; flex-wrap: wrap;">';

        echo '<div style="flex: 1; min-width: 200px; background: #fff; padding: 20px; border-left: 4px solid #00a32a; box-shadow: 0 1px 3px rgba(0,0,0,0.1);">';
        echo '<h3 style="margin: 0 0 10px 0; color: #666; font-size: 14px;">' . esc_html__( 'Total Revenue', 'spvs-cost-profit' ) . '</h3>';
        echo '<p style="font-size: 24px; font-weight: bold; margin: 0; color: #00a32a;">' . wp_kses_post( wc_price( $total_revenue ) ) . '</p>';
        echo '</div>';

        echo '<div style="flex: 1; min-width: 200px; background: #fff; padding: 20px; border-left: 4px solid #d63638; box-shadow: 0 1px 3px rgba(0,0,0,0.1);">';
        echo '<h3 style="margin: 0 0 10px 0; color: #666; font-size: 14px;">' . esc_html__( 'Total Cost', 'spvs-cost-profit' ) . '</h3>';
        echo '<p style="font-size: 24px; font-weight: bold; margin: 0; color: #d63638;">' . wp_kses_post( wc_price( $total_cost ) ) . '</p>';
        echo '</div>';

        echo '<div style="flex: 1; min-width: 200px; background: #fff; padding: 20px; border-left: 4px solid #2271b1; box-shadow: 0 1px 3px rgba(0,0,0,0.1);">';
        echo '<h3 style="margin: 0 0 10px 0; color: #666; font-size: 14px;">' . esc_html__( 'Total Profit', 'spvs-cost-profit' ) . '</h3>';
        echo '<p style="font-size: 24px; font-weight: bold; margin: 0; color: #2271b1;">' . wp_kses_post( wc_price( $total_profit ) ) . '</p>';
        echo '</div>';

        echo '<div style="flex: 1; min-width: 200px; background: #fff; padding: 20px; border-left: 4px solid #ff8c00; box-shadow: 0 1px 3px rgba(0,0,0,0.1);">';
        echo '<h3 style="margin: 0 0 10px 0; color: #666; font-size: 14px;">' . esc_html__( 'Avg Margin', 'spvs-cost-profit' ) . '</h3>';
        echo '<p style="font-size: 24px; font-weight: bold; margin: 0; color: #ff8c00;">' . number_format( $avg_margin, 2 ) . '%</p>';
        echo '</div>';

        echo '</div>';

        // Chart
        echo '<div style="background: #fff; padding: 20px; margin: 20px 0; box-shadow: 0 1px 3px rgba(0,0,0,0.1);">';
        echo '<canvas id="spvs-profit-chart" style="max-height: 400px;"></canvas>';
        echo '</div>';

        // Data table
        $show_table_limit = 100; // Show table if less than 100 periods
        if ( count( $report_data ) <= $show_table_limit ) {
            echo '<div style="background: #fff; padding: 20px; margin: 20px 0; box-shadow: 0 1px 3px rgba(0,0,0,0.1);">';
            echo '<table class="widefat striped">';
            echo '<thead><tr>';
            echo '<th>' . esc_html__( 'Period', 'spvs-cost-profit' ) . '</th>';
            echo '<th>' . esc_html__( 'Orders', 'spvs-cost-profit' ) . '</th>';
            echo '<th>' . esc_html__( 'Revenue', 'spvs-cost-profit' ) . '</th>';
            echo '<th>' . esc_html__( 'Cost', 'spvs-cost-profit' ) . '</th>';
            echo '<th>' . esc_html__( 'Profit', 'spvs-cost-profit' ) . '</th>';
            echo '<th>' . esc_html__( 'Margin %', 'spvs-cost-profit' ) . '</th>';
            echo '<th>' . esc_html__( 'Avg Profit/Order', 'spvs-cost-profit' ) . '</th>';
            echo '</tr></thead><tbody>';

            foreach ( $report_data as $row ) {
                $revenue = (float) $row->total_revenue;
                $cost = (float) $row->total_cost;
                $profit = (float) $row->total_profit;
                $orders = (int) $row->order_count;
                $margin = $revenue > 0 ? ( $profit / $revenue ) * 100 : 0;
                $avg_profit = $orders > 0 ? $profit / $orders : 0;

                echo '<tr>';
                echo '<td><strong>' . esc_html( $row->period ) . '</strong></td>';
                echo '<td>' . esc_html( $orders ) . '</td>';
                echo '<td>' . wp_kses_post( wc_price( $revenue ) ) . '</td>';
                echo '<td>' . wp_kses_post( wc_price( $cost ) ) . '</td>';
                echo '<td>' . wp_kses_post( wc_price( $profit ) ) . '</td>';
                echo '<td>' . number_format( $margin, 2 ) . '%</td>';
                echo '<td>' . wp_kses_post( wc_price( $avg_profit ) ) . '</td>';
                echo '</tr>';
            }

            echo '</tbody></table>';
            echo '</div>';
        } else {
            echo '<div class="notice notice-info"><p>';
            echo esc_html( sprintf( __( 'Detailed table hidden for reports with more than %d periods. Use the chart and summary cards above, or narrow your date range to see the detailed table.', 'spvs-cost-profit' ), $show_table_limit ) );
            echo '</p></div>';
        }

        // Chart.js script
        $currency_symbol = html_entity_decode( get_woocommerce_currency_symbol(), ENT_QUOTES, 'UTF-8' );
        ?>
        <script>
        document.addEventListener('DOMContentLoaded', function() {
            var ctx = document.getElementById('spvs-profit-chart');
            var currencySymbol = <?php echo wp_json_encode( $currency_symbol ); ?>;

            if (ctx && typeof Chart !== 'undefined') {
                new Chart(ctx, {
                    type: 'bar',
                    data: {
                        labels: <?php echo wp_json_encode( $periods ); ?>,
                        datasets: [{
                            label: '<?php echo esc_js( __( 'Revenue', 'spvs-cost-profit' ) ); ?>',
                            data: <?php echo wp_json_encode( $revenues ); ?>,
                            backgroundColor: 'rgba(0, 163, 42, 0.7)',
                            borderColor: 'rgba(0, 163, 42, 1)',
                            borderWidth: 1
                        }, {
                            label: '<?php echo esc_js( __( 'Cost', 'spvs-cost-profit' ) ); ?>',
                            data: <?php echo wp_json_encode( $costs ); ?>,
                            backgroundColor: 'rgba(214, 54, 56, 0.7)',
                            borderColor: 'rgba(214, 54, 56, 1)',
                            borderWidth: 1
                        }, {
                            label: '<?php echo esc_js( __( 'Profit', 'spvs-cost-profit' ) ); ?>',
                            data: <?php echo wp_json_encode( $profits ); ?>,
                            backgroundColor: 'rgba(34, 113, 177, 0.7)',
                            borderColor: 'rgba(34, 113, 177, 1)',
                            borderWidth: 1
                        }]
                    },
                    options: {
                        responsive: true,
                        maintainAspectRatio: true,
                        interaction: {
                            mode: 'index',
                            intersect: false
                        },
                        plugins: {
                            legend: {
                                position: 'top',
                            },
                            title: {
                                display: true,
                                text: '<?php echo esc_js( sprintf( __( '%s Profit Report', 'spvs-cost-profit' ), ucfirst( $grouping ) ) ); ?>'
                            },
                            tooltip: {
                                callbacks: {
                                    label: function(context) {
                                        var label = context.dataset.label || '';
                                        if (label) {
                                            label += ': ';
                                        }
                                        label += currencySymbol + context.parsed.y.toFixed(2);
                                        return label;
                                    }
                                }
                            }
                        },
                        scales: {
                            y: {
                                type: 'linear',
                                display: true,
                                position: 'left',
                                ticks: {
                                    callback: function(value) {
                                        return currencySymbol + value.toFixed(2);
                                    }
                                }
                            }
                        }
                    }
                });
            }
        });
        </script>
        <?php
    }

    private function render_top_products_tab() {
        global $wpdb;

        // Get date range
        $start_date = isset( $_GET['start_date'] ) ? sanitize_text_field( $_GET['start_date'] ) : date( 'Y-m-01' );
        $end_date = isset( $_GET['end_date'] ) ? sanitize_text_field( $_GET['end_date'] ) : date( 'Y-m-d' );
        $limit = isset( $_GET['limit'] ) ? absint( $_GET['limit'] ) : 50;
        if ( $limit < 1 || $limit > 500 ) $limit = 50;

        // Date shortcuts
        $this_month_start = date( 'Y-m-01' );
        $this_month_end = date( 'Y-m-t' );
        $last_month_start = date( 'Y-m-01', strtotime( 'first day of last month' ) );
        $last_month_end = date( 'Y-m-t', strtotime( 'last day of last month' ) );

        echo '<div style="background: #fff; padding: 20px; margin: 20px 0; border: 1px solid #ccc;">';
        echo '<form method="get" id="spvs-top-products-form" style="display: flex; gap: 15px; flex-wrap: wrap; align-items: flex-end;">';
        echo '<input type="hidden" name="page" value="spvs-dashboard" />';
        echo '<input type="hidden" name="tab" value="top-products" />';

        echo '<label><strong>' . esc_html__( 'Start Date:', 'spvs-cost-profit' ) . '</strong><br/>';
        echo '<input type="date" name="start_date" id="spvs-top-start-date" value="' . esc_attr( $start_date ) . '" /></label>';

        echo '<label><strong>' . esc_html__( 'End Date:', 'spvs-cost-profit' ) . '</strong><br/>';
        echo '<input type="date" name="end_date" id="spvs-top-end-date" value="' . esc_attr( $end_date ) . '" /></label>';

        echo '<label><strong>' . esc_html__( 'Show Top:', 'spvs-cost-profit' ) . '</strong><br/>';
        echo '<select name="limit">';
        foreach ( array( 10, 25, 50, 100, 250, 500 ) as $num ) {
            echo '<option value="' . $num . '"' . selected( $limit, $num, false ) . '>' . $num . '</option>';
        }
        echo '</select></label>';

        echo '<button class="button button-primary">' . esc_html__( 'Update', 'spvs-cost-profit' ) . '</button>';

        // Export buttons
        $export_url = add_query_arg( array(
            'action'     => 'spvs_export_top_products',
            '_wpnonce'   => wp_create_nonce( 'spvs_export_top_products' ),
            'start_date' => $start_date,
            'end_date'   => $end_date,
            'limit'      => $limit,
        ), admin_url( 'admin-post.php' ) );
        echo '<a class="button" href="' . esc_url( $export_url ) . '">' . esc_html__( 'Export CSV', 'spvs-cost-profit' ) . '</a>';
        echo '<button type="button" class="button" onclick="window.print();">' . esc_html__( 'Print / Save as PDF', 'spvs-cost-profit' ) . '</button>';

        echo '</form>';

        // Date shortcuts
        echo '<div style="margin-top: 10px; display: flex; gap: 8px;">';
        echo '<strong style="padding: 6px 0;">' . esc_html__( 'Quick Select:', 'spvs-cost-profit' ) . '</strong>';
        echo '<button type="button" class="button spvs-top-date-shortcut" data-start="' . esc_attr( $this_month_start ) . '" data-end="' . esc_attr( $this_month_end ) . '">' . esc_html__( 'This Month', 'spvs-cost-profit' ) . '</button>';
        echo '<button type="button" class="button spvs-top-date-shortcut" data-start="' . esc_attr( $last_month_start ) . '" data-end="' . esc_attr( $last_month_end ) . '">' . esc_html__( 'Last Month', 'spvs-cost-profit' ) . '</button>';
        echo '</div>';

        echo '<script>
        document.addEventListener("DOMContentLoaded", function() {
            document.querySelectorAll(".spvs-top-date-shortcut").forEach(function(btn) {
                btn.addEventListener("click", function() {
                    document.getElementById("spvs-top-start-date").value = this.dataset.start;
                    document.getElementById("spvs-top-end-date").value = this.dataset.end;
                    document.getElementById("spvs-top-products-form").submit();
                });
            });
        });
        </script>';

        echo '</div>';

        // Get top products data
        $order_statuses = array_map( 'esc_sql', array( 'wc-completed', 'wc-processing' ) );
        $status_list = "'" . implode( "','", $order_statuses ) . "'";

        // Try HPOS first, fall back to legacy
        $results = array();
        $orders_table = $wpdb->prefix . 'wc_orders';
        $table_exists = $wpdb->get_var( "SHOW TABLES LIKE '$orders_table'" );

        if ( $table_exists ) {
            // HPOS query
            $query = $wpdb->prepare(
                "SELECT
                    oim_product.meta_value as product_id,
                    SUM(oim_qty.meta_value) as total_qty,
                    SUM(oim_total.meta_value) as total_revenue,
                    SUM(oim_profit.meta_value) as total_profit
                FROM {$wpdb->prefix}woocommerce_order_items oi
                INNER JOIN {$wpdb->prefix}woocommerce_order_itemmeta oim_product
                    ON oi.order_item_id = oim_product.order_item_id
                    AND oim_product.meta_key = '_product_id'
                LEFT JOIN {$wpdb->prefix}woocommerce_order_itemmeta oim_qty
                    ON oi.order_item_id = oim_qty.order_item_id
                    AND oim_qty.meta_key = '_qty'
                LEFT JOIN {$wpdb->prefix}woocommerce_order_itemmeta oim_total
                    ON oi.order_item_id = oim_total.order_item_id
                    AND oim_total.meta_key = '_line_total'
                LEFT JOIN {$wpdb->prefix}woocommerce_order_itemmeta oim_profit
                    ON oi.order_item_id = oim_profit.order_item_id
                    AND oim_profit.meta_key = %s
                INNER JOIN {$orders_table} o ON oi.order_id = o.id
                WHERE o.status IN ($status_list)
                AND o.date_created_gmt >= %s
                AND o.date_created_gmt <= %s
                AND oi.order_item_type = 'line_item'
                GROUP BY product_id
                ORDER BY total_profit DESC
                LIMIT %d",
                self::ORDER_LINE_PROFIT_META,
                $start_date . ' 00:00:00',
                $end_date . ' 23:59:59',
                $limit
            );
            $results = $wpdb->get_results( $query );
        }

        // Fallback to legacy if HPOS query failed or no results
        if ( empty( $results ) ) {
            $query = $wpdb->prepare(
                "SELECT
                    oim_product.meta_value as product_id,
                    SUM(oim_qty.meta_value) as total_qty,
                    SUM(oim_total.meta_value) as total_revenue,
                    SUM(oim_profit.meta_value) as total_profit
                FROM {$wpdb->prefix}woocommerce_order_items oi
                INNER JOIN {$wpdb->prefix}woocommerce_order_itemmeta oim_product
                    ON oi.order_item_id = oim_product.order_item_id
                    AND oim_product.meta_key = '_product_id'
                LEFT JOIN {$wpdb->prefix}woocommerce_order_itemmeta oim_qty
                    ON oi.order_item_id = oim_qty.order_item_id
                    AND oim_qty.meta_key = '_qty'
                LEFT JOIN {$wpdb->prefix}woocommerce_order_itemmeta oim_total
                    ON oi.order_item_id = oim_total.order_item_id
                    AND oim_total.meta_key = '_line_total'
                LEFT JOIN {$wpdb->prefix}woocommerce_order_itemmeta oim_profit
                    ON oi.order_item_id = oim_profit.order_item_id
                    AND oim_profit.meta_key = %s
                INNER JOIN {$wpdb->posts} p ON oi.order_id = p.ID
                WHERE p.post_type = 'shop_order'
                AND p.post_status IN ($status_list)
                AND p.post_date >= %s
                AND p.post_date <= %s
                AND oi.order_item_type = 'line_item'
                GROUP BY product_id
                ORDER BY total_profit DESC
                LIMIT %d",
                self::ORDER_LINE_PROFIT_META,
                $start_date . ' 00:00:00',
                $end_date . ' 23:59:59',
                $limit
            );
            $results = $wpdb->get_results( $query );
        }

        if ( empty( $results ) ) {
            echo '<div class="notice notice-warning"><p>' . esc_html__( 'No product data found for the selected date range.', 'spvs-cost-profit' ) . '</p></div>';
            return;
        }

        // Display results
        echo '<div style="background: #fff; padding: 20px; margin: 20px 0; box-shadow: 0 1px 3px rgba(0,0,0,0.1); overflow-x: auto;">';
        echo '<h3>' . esc_html( sprintf( __( 'Top %d Products by Profit', 'spvs-cost-profit' ), count( $results ) ) ) . '</h3>';
        echo '<table class="widefat striped">';
        echo '<thead><tr>';
        echo '<th style="width: 50px;">' . esc_html__( 'Rank', 'spvs-cost-profit' ) . '</th>';
        echo '<th>' . esc_html__( 'Product', 'spvs-cost-profit' ) . '</th>';
        echo '<th>' . esc_html__( 'SKU', 'spvs-cost-profit' ) . '</th>';
        echo '<th style="text-align: right;">' . esc_html__( 'Qty Sold', 'spvs-cost-profit' ) . '</th>';
        echo '<th style="text-align: right;">' . esc_html__( 'Revenue', 'spvs-cost-profit' ) . '</th>';
        echo '<th style="text-align: right;">' . esc_html__( 'Profit', 'spvs-cost-profit' ) . '</th>';
        echo '<th style="text-align: right;">' . esc_html__( 'Margin %', 'spvs-cost-profit' ) . '</th>';
        echo '<th style="text-align: right;">' . esc_html__( 'Avg Profit/Unit', 'spvs-cost-profit' ) . '</th>';
        echo '</tr></thead><tbody>';

        $rank = 1;
        foreach ( $results as $row ) {
            $product = wc_get_product( $row->product_id );
            if ( ! $product ) continue;

            $qty = (int) $row->total_qty;
            $revenue = (float) $row->total_revenue;
            $profit = (float) $row->total_profit;
            $margin = $revenue > 0 ? ( $profit / $revenue ) * 100 : 0;
            $avg_profit = $qty > 0 ? $profit / $qty : 0;

            echo '<tr>';
            echo '<td style="text-align: center;"><strong>' . $rank . '</strong></td>';
            echo '<td><a href="' . esc_url( get_edit_post_link( $product->get_id() ) ) . '" target="_blank">' . esc_html( $product->get_name() ) . '</a></td>';
            echo '<td>' . esc_html( $product->get_sku() ) . '</td>';
            echo '<td style="text-align: right;">' . esc_html( $qty ) . '</td>';
            echo '<td style="text-align: right;">' . wp_kses_post( wc_price( $revenue ) ) . '</td>';
            echo '<td style="text-align: right;"><strong>' . wp_kses_post( wc_price( $profit ) ) . '</strong></td>';
            echo '<td style="text-align: right;">' . number_format( $margin, 2 ) . '%</td>';
            echo '<td style="text-align: right;">' . wp_kses_post( wc_price( $avg_profit ) ) . '</td>';
            echo '</tr>';

            $rank++;
        }

        echo '</tbody></table>';
        echo '</div>';
    }

    private function render_inventory_tab() {
        global $wpdb;

        $totals = get_option( self::INVENTORY_TOTALS_OPTION, array() );
        $tcop   = isset( $totals['tcop'] ) ? (float) $totals['tcop'] : 0.0;
        $retail = isset( $totals['retail'] ) ? (float) $totals['retail'] : 0.0;
        $updated = isset( $totals['updated'] ) ? (int) $totals['updated'] : 0;
        $count   = isset( $totals['count'] ) ? (int) $totals['count'] : 0;
        $managed = isset( $totals['managed'] ) ? (int) $totals['managed'] : 0;
        $qty_gt0 = isset( $totals['qty_gt0'] ) ? (int) $totals['qty_gt0'] : 0;

        // Summary cards
        echo '<div style="display: flex; gap: 20px; margin: 20px 0; flex-wrap: wrap;">';

        echo '<div style="flex: 1; min-width: 200px; background: #fff; padding: 20px; border-left: 4px solid #2271b1; box-shadow: 0 1px 3px rgba(0,0,0,0.1);">';
        echo '<h3 style="margin: 0 0 10px 0; color: #666; font-size: 14px;">' . esc_html__( 'TCOP (Total Cost)', 'spvs-cost-profit' ) . '</h3>';
        echo '<p style="font-size: 24px; font-weight: bold; margin: 0; color: #2271b1;">' . wp_kses_post( wc_price( $tcop ) ) . '</p>';
        echo '</div>';

        echo '<div style="flex: 1; min-width: 200px; background: #fff; padding: 20px; border-left: 4px solid #00a32a; box-shadow: 0 1px 3px rgba(0,0,0,0.1);">';
        echo '<h3 style="margin: 0 0 10px 0; color: #666; font-size: 14px;">' . esc_html__( 'Retail Total', 'spvs-cost-profit' ) . '</h3>';
        echo '<p style="font-size: 24px; font-weight: bold; margin: 0; color: #00a32a;">' . wp_kses_post( wc_price( $retail ) ) . '</p>';
        echo '</div>';

        echo '<div style="flex: 1; min-width: 200px; background: #fff; padding: 20px; border-left: 4px solid #ff8c00; box-shadow: 0 1px 3px rgba(0,0,0,0.1);">';
        echo '<h3 style="margin: 0 0 10px 0; color: #666; font-size: 14px;">' . esc_html__( 'Spread', 'spvs-cost-profit' ) . '</h3>';
        echo '<p style="font-size: 24px; font-weight: bold; margin: 0; color: #ff8c00;">' . wp_kses_post( wc_price( $retail - $tcop ) ) . '</p>';
        echo '</div>';

        echo '</div>';

        // Stats
        echo '<div style="background: #fff; padding: 15px; margin: 20px 0; border: 1px solid #ccc;">';
        if ( $updated ) {
            echo '<p style="margin: 0 0 10px 0;"><strong>' . esc_html__( 'Last Updated:', 'spvs-cost-profit' ) . '</strong> ' . esc_html( human_time_diff( $updated, time() ) ) . ' ' . esc_html__( 'ago', 'spvs-cost-profit' ) . '</p>';
        }
        echo '<p style="margin: 0;"><strong>' . esc_html__( 'Items processed:', 'spvs-cost-profit' ) . '</strong> ' . esc_html( $count ) . ' · ';
        echo '<strong>' . esc_html__( 'Managing stock:', 'spvs-cost-profit' ) . '</strong> ' . esc_html( $managed ) . ' · ';
        echo '<strong>' . esc_html__( 'Qty > 0:', 'spvs-cost-profit' ) . '</strong> ' . esc_html( $qty_gt0 ) . '</p>';
        echo '<p style="margin: 10px 0 0 0; opacity: 0.8; font-size: 13px;">' . esc_html__( 'Note: If a variation has no cost set, it will use the parent product cost automatically.', 'spvs-cost-profit' ) . '</p>';
        echo '<p style="margin: 10px 0 0 0;">';
        echo '<a class="button button-primary" href="' . esc_url( admin_url( 'admin-post.php?action=spvs_recalc_inventory&_wpnonce=' . wp_create_nonce( 'spvs_recalc_inventory' ) ) ) . '">' . esc_html__( 'Recalculate Now', 'spvs-cost-profit' ) . '</a>';
        echo '</p>';
        echo '</div>';

        // Column picker and export
        $available = $this->spvs_get_available_columns();
        $default_cols = array( 'sku', 'name', 'qty', 'cost', 'regular_price' );
        $selected = isset( $_GET['spvs_cols'] ) ? array_map( 'sanitize_text_field', (array) $_GET['spvs_cols'] ) : $default_cols;
        $selected = array_values( array_intersect( array_keys( $available ), $selected ) );
        if ( empty( $selected ) ) $selected = $default_cols;

        $export_url = add_query_arg( array(
            'action'    => 'spvs_export_inventory_csv',
            '_wpnonce'  => wp_create_nonce( 'spvs_export_inventory_csv' ),
            'spvs_cols' => $selected,
        ), admin_url( 'admin-post.php' ) );

        echo '<div style="background: #fff; padding: 20px; margin: 20px 0; border: 1px solid #ccc;">';
        echo '<h3>' . esc_html__( 'Inventory Preview & Export', 'spvs-cost-profit' ) . '</h3>';
        echo '<form method="get" style="margin: 15px 0; display:flex; align-items:flex-end; gap:12px; flex-wrap:wrap;">';
        echo '<input type="hidden" name="page" value="spvs-dashboard" />';
        echo '<input type="hidden" name="tab" value="inventory" />';
        echo '<label><strong>' . esc_html__( 'Columns:', 'spvs-cost-profit' ) . '</strong><br/>';
        echo '<select name="spvs_cols[]" multiple size="6" style="min-width:220px;">';
        foreach ( $available as $key => $label ) {
            $sel = in_array( $key, $selected, true ) ? ' selected' : '';
            echo '<option value="' . esc_attr( $key ) . '"' . $sel . '>' . esc_html( $label ) . '</option>';
        }
        echo '</select></label>';
        echo '<button class="button">' . esc_html__( 'Apply', 'spvs-cost-profit' ) . '</button>';
        echo '<a class="button button-primary" href="' . esc_url( $export_url ) . '">' . esc_html__( 'Export CSV', 'spvs-cost-profit' ) . '</a>';
        echo '<a class="button" href="' . esc_url( admin_url( 'admin-post.php?action=spvs_cost_missing_csv' ) ) . '">' . esc_html__( 'Download Missing Costs', 'spvs-cost-profit' ) . '</a>';
        echo '</form>';

        // Preview top 100 rows
        $q = new WP_Query( array( 'post_type' => array( 'product', 'product_variation' ), 'post_status' => 'publish', 'posts_per_page' => 100, 'fields' => 'ids', 'no_found_rows' => true ) );
        echo '<div style="overflow-x: auto;">';
        echo '<table class="widefat striped"><thead><tr>';
        foreach ( $selected as $key ) echo '<th>' . esc_html( $available[ $key ] ) . '</th>';
        echo '</tr></thead><tbody>';
        if ( $q->have_posts() ) {
            foreach ( $q->posts as $pid ) {
                $product = wc_get_product( $pid ); if ( ! $product ) continue;
                $row = $this->spvs_build_row_for_columns( $product, $selected );
                echo '<tr>';
                foreach ( $row as $cell ) echo '<td>' . esc_html( is_array( $cell ) ? implode( ', ', $cell ) : (string) $cell ) . '</td>';
                echo '</tr>';
            }
        } else {
            echo '<tr><td colspan="' . count( $selected ) . '">' . esc_html__( 'No items found.', 'spvs-cost-profit' ) . '</td></tr>';
        }
        echo '</tbody></table>';
        echo '</div>';
        echo '</div>';
    }

    private function render_import_tab() {
        global $wpdb;

        // Count products with COG data
        $cog_count = $wpdb->get_var( "
            SELECT COUNT(*) FROM {$wpdb->postmeta}
            WHERE meta_key = '_wc_cog_cost'
            AND meta_value != ''
            AND meta_value != '0'
        " );

        // Display notices
        if ( isset( $_GET['spvs_msg'] ) ) {
            $m = sanitize_text_field( wp_unslash( $_GET['spvs_msg'] ) );
            if ( 'no_file' === $m ) {
                echo '<div class="notice notice-error"><p>' . esc_html__( 'No file uploaded.', 'spvs-cost-profit' ) . '</p></div>';
            } elseif ( 'open_fail' === $m ) {
                echo '<div class="notice notice-error"><p>' . esc_html__( 'Could not open uploaded file.', 'spvs-cost-profit' ) . '</p></div>';
            } elseif ( 'missing_cost_col' === $m ) {
                echo '<div class="notice notice-error"><p>' . esc_html__( 'Missing "cost" column in CSV header.', 'spvs-cost-profit' ) . '</p></div>';
            } elseif ( 0 === strpos( $m, 'import_done:' ) ) {
                $parts = explode( ':', $m );
                if ( count( $parts ) === 5 ) {
                    printf( '<div class="notice notice-success"><p>%s</p></div>',
                        esc_html( sprintf( __( 'Import finished. Total: %d, Updated: %d, Skipped: %d, Errors: %d', 'spvs-cost-profit' ), (int)$parts[1], (int)$parts[2], (int)$parts[3], (int)$parts[4] ) )
                    );
                    if ( get_transient( self::IMPORT_MISSES_TRANSIENT ) ) {
                        $miss_url = esc_url( admin_url( 'admin-post.php?action=spvs_cost_import_misses' ) );
                        echo '<div class="notice"><p>' . sprintf( esc_html__( 'Some rows did not match any product. You can %s.', 'spvs-cost-profit' ), '<a class="button" href="' . $miss_url . '">' . esc_html__( 'download unmatched rows', 'spvs-cost-profit' ) . '</a>' ) . '</p></div>';
                    }
                }
            } elseif ( 0 === strpos( $m, 'cog_import_done:' ) ) {
                $parts = explode( ':', $m );
                if ( count( $parts ) === 4 ) {
                    printf( '<div class="notice notice-success"><p>%s</p></div>',
                        esc_html( sprintf( __( 'COG import finished. Imported: %d, Updated: %d, Skipped: %d', 'spvs-cost-profit' ), (int)$parts[1], (int)$parts[2], (int)$parts[3] ) )
                    );
                }
            } elseif ( 0 === strpos( $m, 'profit_recalc_done:' ) ) {
                $parts = explode( ':', $m );
                if ( count( $parts ) === 3 ) {
                    printf( '<div class="notice notice-success"><p>%s</p></div>',
                        esc_html( sprintf( __( 'Historical profit recalculation completed. Processed %d order items. %d products have cost data.', 'spvs-cost-profit' ), (int)$parts[1], (int)$parts[2] ) )
                    );
                    if ( (int)$parts[2] === 0 ) {
                        echo '<div class="notice notice-warning"><p>' . esc_html__( 'Warning: No products have cost data. Please import costs first or set costs manually on products.', 'spvs-cost-profit' ) . '</p></div>';
                    }
                }
            } elseif ( 0 === strpos( $m, 'profit_recalc_error:' ) ) {
                $error_msg = str_replace( 'profit_recalc_error:', '', $m );
                printf( '<div class="notice notice-error"><p>%s</p></div>',
                    esc_html( sprintf( __( 'Historical profit recalculation failed: %s', 'spvs-cost-profit' ), $error_msg ) )
                );
            }
        }

        // COG Import Section
        echo '<div style="background: #fff; padding: 20px; margin: 20px 0; border: 1px solid #ccc;">';
        echo '<h3>' . esc_html__( 'Import from Cost of Goods Plugin', 'spvs-cost-profit' ) . '</h3>';
        echo '<p>' . esc_html__( 'Found', 'spvs-cost-profit' ) . ' <strong>' . esc_html( $cog_count ) . '</strong> ' . esc_html__( 'products with Cost of Goods data.', 'spvs-cost-profit' ) . '</p>';
        echo '<form method="post" action="' . esc_url( admin_url( 'admin-post.php' ) ) . '" onsubmit="return confirm(\'Import costs from Cost of Goods plugin? This may take a moment.\');">';
        echo '<input type="hidden" name="action" value="spvs_import_cog" />';
        wp_nonce_field( 'spvs_import_cog' );
        echo '<p><label><input type="checkbox" name="spvs_cog_overwrite" value="1"> ' . esc_html__( 'Overwrite existing cost values', 'spvs-cost-profit' ) . '</label></p>';
        echo '<p><label><input type="checkbox" name="spvs_cog_delete_after" value="1"> ' . esc_html__( 'Delete Cost of Goods data after import', 'spvs-cost-profit' ) . '</label></p>';
        echo '<button type="submit" class="button button-primary">' . esc_html__( 'Import from Cost of Goods', 'spvs-cost-profit' ) . '</button>';
        echo '<p class="description" style="margin-top: 10px;">' . esc_html__( 'This will import all cost data from the WooCommerce Cost of Goods plugin. Direct server processing.', 'spvs-cost-profit' ) . '</p>';
        echo '</form>';
        echo '</div>';

        // CSV Cost Import Section
        echo '<div style="background: #fff; padding: 20px; margin: 20px 0; border: 1px solid #ccc;">';
        echo '<h3>' . esc_html__( 'Import Costs from CSV', 'spvs-cost-profit' ) . '</h3>';
        echo '<p><a class="button" href="' . esc_url( admin_url( 'admin-post.php?action=spvs_cost_template_csv' ) ) . '">' . esc_html__( 'Download Template CSV', 'spvs-cost-profit' ) . '</a></p>';
        echo '<form method="post" action="' . esc_url( admin_url( 'admin-post.php' ) ) . '" enctype="multipart/form-data" style="margin-top: 15px;">';
        echo '<input type="hidden" name="action" value="spvs_import_costs_csv" />';
        wp_nonce_field( 'spvs_import_costs_csv' );
        echo '<p><label><strong>' . esc_html__( 'CSV file:', 'spvs-cost-profit' ) . '</strong><br>';
        echo '<input type="file" name="spvs_costs_file" accept=".csv,text/csv" required /></label></p>';
        echo '<p><label><input type="checkbox" name="spvs_recalc_after" value="1" /> ' . esc_html__( 'Recalculate inventory totals after import', 'spvs-cost-profit' ) . '</label></p>';
        echo '<button class="button button-primary">' . esc_html__( 'Import Costs', 'spvs-cost-profit' ) . '</button>';
        echo '<p class="description" style="margin-top: 10px;">' . esc_html__( 'Accepted columns: SKU, Product ID (or variation_id), Slug (parent only), Cost. Header row required: any of "sku" or "product_id"/"variation_id", and "cost".', 'spvs-cost-profit' ) . '</p>';
        echo '</form>';
        echo '</div>';
    }

    private function render_health_tab() {
        global $wpdb;

        // Run integrity checks
        $checks = array();

        // 1. Check for orders without profit data
        $orders_table = $wpdb->prefix . 'wc_orders';
        $table_exists = $wpdb->get_var( "SHOW TABLES LIKE '$orders_table'" );

        if ( $table_exists ) {
            $missing_profit_orders = $wpdb->get_var( $wpdb->prepare(
                "SELECT COUNT(*) FROM {$orders_table} o
                LEFT JOIN {$wpdb->prefix}wc_orders_meta om ON o.id = om.order_id AND om.meta_key = %s
                WHERE o.status IN ('wc-completed', 'wc-processing')
                AND o.date_created_gmt >= %s
                AND (om.meta_value IS NULL OR om.meta_value = '')",
                self::ORDER_TOTAL_PROFIT_META,
                date( 'Y-m-d H:i:s', strtotime( '-90 days' ) )
            ) );
        } else {
            $missing_profit_orders = $wpdb->get_var( $wpdb->prepare(
                "SELECT COUNT(*) FROM {$wpdb->posts} p
                LEFT JOIN {$wpdb->postmeta} pm ON p.ID = pm.post_id AND pm.meta_key = %s
                WHERE p.post_type = 'shop_order'
                AND p.post_status IN ('wc-completed', 'wc-processing')
                AND p.post_date >= %s
                AND (pm.meta_value IS NULL OR pm.meta_value = '')",
                self::ORDER_TOTAL_PROFIT_META,
                date( 'Y-m-d H:i:s', strtotime( '-90 days' ) )
            ) );
        }

        $checks['missing_profit'] = array(
            'label'  => __( 'Orders Missing Profit Data (last 90 days)', 'spvs-cost-profit' ),
            'count'  => $missing_profit_orders,
            'status' => $missing_profit_orders == 0 ? 'good' : 'warning',
        );

        // 2. Check for products with stock but no cost
        $missing_cost = $wpdb->get_var( "
            SELECT COUNT(DISTINCT p.ID)
            FROM {$wpdb->posts} p
            LEFT JOIN {$wpdb->postmeta} pm_cost ON p.ID = pm_cost.post_id AND pm_cost.meta_key = '" . self::PRODUCT_COST_META . "'
            LEFT JOIN {$wpdb->postmeta} pm_stock ON p.ID = pm_stock.post_id AND pm_stock.meta_key = '_stock'
            LEFT JOIN {$wpdb->postmeta} pm_stock_status ON p.ID = pm_stock_status.post_id AND pm_stock_status.meta_key = '_stock_status'
            WHERE p.post_type IN ('product', 'product_variation')
            AND p.post_status = 'publish'
            AND pm_stock_status.meta_value = 'instock'
            AND (pm_stock.meta_value IS NOT NULL AND CAST(pm_stock.meta_value AS DECIMAL) > 0)
            AND (pm_cost.meta_value IS NULL OR pm_cost.meta_value = '' OR CAST(pm_cost.meta_value AS DECIMAL) = 0)
        " );

        $checks['missing_cost'] = array(
            'label'  => __( 'Products In Stock Without Cost', 'spvs-cost-profit' ),
            'count'  => $missing_cost,
            'status' => $missing_cost == 0 ? 'good' : 'error',
        );

        // 3. Audit log statistics
        $audit_table = $wpdb->prefix . 'spvs_cost_audit';
        $audit_exists = $wpdb->get_var( "SHOW TABLES LIKE '$audit_table'" );

        if ( $audit_exists ) {
            $audit_count = $wpdb->get_var( "SELECT COUNT(*) FROM $audit_table WHERE created_at >= DATE_SUB(NOW(), INTERVAL 30 DAY)" );
            $audit_recent = $wpdb->get_var( "SELECT COUNT(*) FROM $audit_table WHERE created_at >= DATE_SUB(NOW(), INTERVAL 7 DAY)" );

            $checks['audit_log'] = array(
                'label'  => __( 'Cost Changes (last 30 days)', 'spvs-cost-profit' ),
                'count'  => $audit_count,
                'status' => 'info',
                'extra'  => sprintf( __( '%d in last 7 days', 'spvs-cost-profit' ), $audit_recent ),
            );
        } else {
            $checks['audit_log'] = array(
                'label'  => __( 'Audit Log Table', 'spvs-cost-profit' ),
                'count'  => 0,
                'status' => 'error',
                'extra'  => __( 'Table not found', 'spvs-cost-profit' ),
            );
        }

        // 4. Last integrity check
        $last_check = get_option( self::INTEGRITY_CHECK_OPTION, 0 );
        $checks['last_check'] = array(
            'label'  => __( 'Last Integrity Check', 'spvs-cost-profit' ),
            'count'  => '',
            'status' => 'info',
            'extra'  => $last_check ? human_time_diff( $last_check, time() ) . ' ' . __( 'ago', 'spvs-cost-profit' ) : __( 'Never', 'spvs-cost-profit' ),
        );

        // Display health dashboard
        echo '<div style="background: #fff; padding: 20px; margin: 20px 0; border: 1px solid #ccc;">';
        echo '<h3>' . esc_html__( 'Data Integrity Status', 'spvs-cost-profit' ) . '</h3>';

        echo '<table class="widefat striped">';
        echo '<thead><tr>';
        echo '<th>' . esc_html__( 'Check', 'spvs-cost-profit' ) . '</th>';
        echo '<th style="width: 100px;">' . esc_html__( 'Status', 'spvs-cost-profit' ) . '</th>';
        echo '<th style="width: 150px;">' . esc_html__( 'Count/Info', 'spvs-cost-profit' ) . '</th>';
        echo '</tr></thead><tbody>';

        foreach ( $checks as $check_key => $check ) {
            $status_color = array(
                'good'    => '#00a32a',
                'warning' => '#ff8c00',
                'error'   => '#d63638',
                'info'    => '#2271b1',
            );

            $status_text = array(
                'good'    => '✓ ' . __( 'Good', 'spvs-cost-profit' ),
                'warning' => '⚠ ' . __( 'Warning', 'spvs-cost-profit' ),
                'error'   => '✗ ' . __( 'Error', 'spvs-cost-profit' ),
                'info'    => 'ℹ ' . __( 'Info', 'spvs-cost-profit' ),
            );

            $color = $status_color[ $check['status'] ];
            $status = $status_text[ $check['status'] ];

            echo '<tr>';
            echo '<td><strong>' . esc_html( $check['label'] ) . '</strong></td>';
            echo '<td style="color: ' . esc_attr( $color ) . '; font-weight: bold;">' . esc_html( $status ) . '</td>';
            echo '<td>' . esc_html( $check['count'] ) . ( isset( $check['extra'] ) ? '<br><small>' . esc_html( $check['extra'] ) . '</small>' : '' ) . '</td>';
            echo '</tr>';
        }

        echo '</tbody></table>';

        echo '<p style="margin-top: 20px;">';
        echo '<a href="' . esc_url( add_query_arg( array( 'page' => 'spvs-dashboard', 'tab' => 'health', 'action' => 'run_integrity_check' ), admin_url( 'admin.php' ) ) ) . '" class="button button-primary">' . esc_html__( 'Run Full Integrity Check', 'spvs-cost-profit' ) . '</a>';
        echo ' <a href="' . esc_url( add_query_arg( array( 'page' => 'spvs-dashboard', 'tab' => 'health', 'action' => 'fix_missing_profit' ), admin_url( 'admin.php' ) ) ) . '" class="button">' . esc_html__( 'Fix Missing Profit Data', 'spvs-cost-profit' ) . '</a>';
        echo ' <button type="button" class="button" id="spvs-recalc-profit-btn">' . esc_html__( 'Recalculate Historical Profit', 'spvs-cost-profit' ) . '</button>';
        echo ' <a href="' . esc_url( add_query_arg( array( 'page' => 'spvs-dashboard', 'tab' => 'health', 'action' => 'cleanup_audit' ), admin_url( 'admin.php' ) ) ) . '" class="button">' . esc_html__( 'Cleanup Old Audit Logs', 'spvs-cost-profit' ) . '</a>';
        echo '</p>';

        // Progress bar for historical profit recalculation
        echo '<div id="spvs-recalc-progress" style="display: none; margin-top: 20px; padding: 15px; background: #f0f0f1; border: 1px solid #ccc; border-radius: 4px;">';
        echo '<div style="margin-bottom: 10px;"><strong>' . esc_html__( 'Recalculating Historical Profit...', 'spvs-cost-profit' ) . '</strong></div>';
        echo '<div style="background: #fff; border: 1px solid #ddd; height: 30px; border-radius: 3px; overflow: hidden; position: relative;">';
        echo '<div id="spvs-recalc-progress-bar" style="height: 100%; background: linear-gradient(to right, #00a32a, #00d084); width: 0%; transition: width 0.3s;"></div>';
        echo '<div id="spvs-recalc-progress-text" style="position: absolute; top: 50%; left: 50%; transform: translate(-50%, -50%); font-weight: bold; color: #333;">0%</div>';
        echo '</div>';
        echo '<div id="spvs-recalc-status" style="margin-top: 10px; font-size: 13px; color: #666;"></div>';
        echo '</div>';

        // JavaScript for batch processing
        ?>
        <script>
        (function($) {
            var processing = false;
            var nonce = '<?php echo wp_create_nonce( 'spvs_recalc_profit' ); ?>';

            $('#spvs-recalc-profit-btn').on('click', function() {
                if (processing) return;

                if (!confirm('<?php echo esc_js( __( 'This will recalculate profit for ALL historical orders. This process may take several minutes depending on the number of orders. Continue?', 'spvs-cost-profit' ) ); ?>')) {
                    return;
                }

                processing = true;
                $(this).prop('disabled', true).text('<?php echo esc_js( __( 'Processing...', 'spvs-cost-profit' ) ); ?>');
                $('#spvs-recalc-progress').show();
                $('#spvs-recalc-status').text('<?php echo esc_js( __( 'Initializing...', 'spvs-cost-profit' ) ); ?>');

                // Get total count first
                $.ajax({
                    url: ajaxurl,
                    type: 'POST',
                    data: {
                        action: 'spvs_get_recalc_count',
                        nonce: nonce
                    },
                    success: function(response) {
                        if (response.success) {
                            var total = response.data.total;
                            var productsWithCosts = response.data.products_with_costs;

                            if (productsWithCosts === 0) {
                                alert('<?php echo esc_js( __( 'Warning: No products have cost data. Please import costs first.', 'spvs-cost-profit' ) ); ?>');
                                resetButton();
                                return;
                            }

                            $('#spvs-recalc-status').html('<?php echo esc_js( __( 'Processing {total} order items...', 'spvs-cost-profit' ) ); ?>'.replace('{total}', total.toLocaleString()));
                            processBatch(0, total);
                        } else {
                            alert('<?php echo esc_js( __( 'Error: Could not get count.', 'spvs-cost-profit' ) ); ?>');
                            resetButton();
                        }
                    },
                    error: function() {
                        alert('<?php echo esc_js( __( 'AJAX error occurred.', 'spvs-cost-profit' ) ); ?>');
                        resetButton();
                    }
                });
            });

            function processBatch(offset, total) {
                var batchSize = 100;
                var processed = offset;

                $.ajax({
                    url: ajaxurl,
                    type: 'POST',
                    data: {
                        action: 'spvs_recalc_batch',
                        nonce: nonce,
                        offset: offset
                    },
                    success: function(response) {
                        if (response.success) {
                            processed += response.data.processed;
                            var percentage = total > 0 ? Math.min(100, Math.round((processed / total) * 100)) : 100;

                            $('#spvs-recalc-progress-bar').css('width', percentage + '%');
                            $('#spvs-recalc-progress-text').text(percentage + '%');
                            $('#spvs-recalc-status').html('<?php echo esc_js( __( 'Processed {processed} of {total} items ({orders} orders updated)...', 'spvs-cost-profit' ) ); ?>'
                                .replace('{processed}', processed.toLocaleString())
                                .replace('{total}', total.toLocaleString())
                                .replace('{orders}', response.data.orders_updated.toLocaleString())
                            );

                            if (processed < total) {
                                // Continue processing
                                setTimeout(function() {
                                    processBatch(offset + batchSize, total);
                                }, 500); // Small delay between batches
                            } else {
                                // Complete
                                $('#spvs-recalc-status').html('<span style="color: #00a32a; font-weight: bold;">✓ <?php echo esc_js( __( 'Complete! Processed {processed} items.', 'spvs-cost-profit' ) ); ?></span>'
                                    .replace('{processed}', processed.toLocaleString())
                                );
                                setTimeout(function() {
                                    location.reload();
                                }, 2000);
                            }
                        } else {
                            alert('<?php echo esc_js( __( 'Error processing batch.', 'spvs-cost-profit' ) ); ?>');
                            resetButton();
                        }
                    },
                    error: function() {
                        alert('<?php echo esc_js( __( 'AJAX error during batch processing.', 'spvs-cost-profit' ) ); ?>');
                        resetButton();
                    }
                });
            }

            function resetButton() {
                processing = false;
                $('#spvs-recalc-profit-btn').prop('disabled', false).text('<?php echo esc_js( __( 'Recalculate Historical Profit', 'spvs-cost-profit' ) ); ?>');
                $('#spvs-recalc-progress').hide();
            }
        })(jQuery);
        </script>
        <?php

        // Handle actions
        if ( isset( $_GET['action'] ) && current_user_can( 'manage_woocommerce' ) ) {
            $action = sanitize_text_field( $_GET['action'] );

            if ( 'run_integrity_check' === $action ) {
                update_option( self::INTEGRITY_CHECK_OPTION, time() );
                echo '<div class="notice notice-success"><p>' . esc_html__( 'Integrity check completed. Results updated above.', 'spvs-cost-profit' ) . '</p></div>';
            }

            if ( 'fix_missing_profit' === $action && $missing_profit_orders > 0 ) {
                $fixed = $this->fix_missing_profit_data();
                echo '<div class="notice notice-success"><p>' . sprintf( esc_html__( 'Fixed %d orders with missing profit data.', 'spvs-cost-profit' ), $fixed ) . '</p></div>';
            }

            if ( 'cleanup_audit' === $action ) {
                $this->cleanup_old_audit_logs();
                echo '<div class="notice notice-success"><p>' . esc_html__( 'Audit logs older than 90 days have been cleaned up.', 'spvs-cost-profit' ) . '</p></div>';
            }
        }

        echo '</div>';

        // Recent audit log
        if ( $audit_exists ) {
            echo '<div style="background: #fff; padding: 20px; margin: 20px 0; border: 1px solid #ccc;">';
            echo '<h3>' . esc_html__( 'Recent Cost Changes', 'spvs-cost-profit' ) . '</h3>';

            $recent_logs = $wpdb->get_results( "
                SELECT a.*, p.post_title, u.display_name
                FROM $audit_table a
                LEFT JOIN {$wpdb->posts} p ON a.product_id = p.ID
                LEFT JOIN {$wpdb->users} u ON a.user_id = u.ID
                ORDER BY a.created_at DESC
                LIMIT 50
            " );

            if ( ! empty( $recent_logs ) ) {
                echo '<table class="widefat striped"><thead><tr>';
                echo '<th>' . esc_html__( 'Date', 'spvs-cost-profit' ) . '</th>';
                echo '<th>' . esc_html__( 'Product', 'spvs-cost-profit' ) . '</th>';
                echo '<th>' . esc_html__( 'Action', 'spvs-cost-profit' ) . '</th>';
                echo '<th>' . esc_html__( 'Old Cost', 'spvs-cost-profit' ) . '</th>';
                echo '<th>' . esc_html__( 'New Cost', 'spvs-cost-profit' ) . '</th>';
                echo '<th>' . esc_html__( 'Source', 'spvs-cost-profit' ) . '</th>';
                echo '<th>' . esc_html__( 'User', 'spvs-cost-profit' ) . '</th>';
                echo '</tr></thead><tbody>';

                foreach ( $recent_logs as $log ) {
                    echo '<tr>';
                    echo '<td>' . esc_html( date_i18n( 'Y-m-d H:i', strtotime( $log->created_at ) ) ) . '</td>';
                    echo '<td><a href="' . esc_url( get_edit_post_link( $log->product_id ) ) . '" target="_blank">' . esc_html( $log->post_title ? $log->post_title : '#' . $log->product_id ) . '</a></td>';
                    echo '<td>' . esc_html( $log->action ) . '</td>';
                    echo '<td>' . ( $log->old_cost ? wp_kses_post( wc_price( $log->old_cost ) ) : '—' ) . '</td>';
                    echo '<td>' . ( $log->new_cost ? wp_kses_post( wc_price( $log->new_cost ) ) : '—' ) . '</td>';
                    echo '<td>' . esc_html( $log->source ) . '</td>';
                    echo '<td>' . esc_html( $log->display_name ? $log->display_name : '—' ) . '</td>';
                    echo '</tr>';
                }

                echo '</tbody></table>';
            } else {
                echo '<p>' . esc_html__( 'No recent cost changes found.', 'spvs-cost-profit' ) . '</p>';
            }

            echo '</div>';
        }
    }

    private function fix_missing_profit_data() {
        global $wpdb;

        // Try HPOS first
        $orders_table = $wpdb->prefix . 'wc_orders';
        $table_exists = $wpdb->get_var( "SHOW TABLES LIKE '$orders_table'" );

        $fixed = 0;

        if ( $table_exists ) {
            $order_ids = $wpdb->get_col( $wpdb->prepare(
                "SELECT DISTINCT o.id FROM {$orders_table} o
                LEFT JOIN {$wpdb->prefix}wc_orders_meta om ON o.id = om.order_id AND om.meta_key = %s
                WHERE o.status IN ('wc-completed', 'wc-processing')
                AND o.date_created_gmt >= %s
                AND (om.meta_value IS NULL OR om.meta_value = '')
                LIMIT 500",
                self::ORDER_TOTAL_PROFIT_META,
                date( 'Y-m-d H:i:s', strtotime( '-90 days' ) )
            ) );
        } else {
            $order_ids = $wpdb->get_col( $wpdb->prepare(
                "SELECT DISTINCT p.ID FROM {$wpdb->posts} p
                LEFT JOIN {$wpdb->postmeta} pm ON p.ID = pm.post_id AND pm.meta_key = %s
                WHERE p.post_type = 'shop_order'
                AND p.post_status IN ('wc-completed', 'wc-processing')
                AND p.post_date >= %s
                AND (pm.meta_value IS NULL OR pm.meta_value = '')
                LIMIT 500",
                self::ORDER_TOTAL_PROFIT_META,
                date( 'Y-m-d H:i:s', strtotime( '-90 days' ) )
            ) );
        }

        foreach ( $order_ids as $order_id ) {
            $order = wc_get_order( $order_id );
            if ( $order ) {
                $this->recalculate_order_total_profit( $order );
                $fixed++;
            }

            if ( $fixed % 100 === 0 ) {
                usleep( 100000 ); // Rate limiting
            }
        }

        return $fixed;
    }

    /**
     * Recalculate historical profit for all orders
     *
     * This function performs a bulk recalculation of profit data for all historical orders.
     * It's useful when costs have been imported after orders were placed.
     *
     * Process:
     * 1. Add unit costs to order items from current product costs
     * 2. Calculate line profit (revenue - cost × qty)
     * 3. Calculate total profit per order
     */
    public function recalculate_historical_profit() {
        if ( ! current_user_can( 'manage_woocommerce' ) ) {
            wp_die( esc_html__( 'Insufficient permissions.', 'spvs-cost-profit' ) );
        }

        check_admin_referer( 'spvs_recalc_profit' );

        global $wpdb;

        // Prevent SQL errors from breaking the process
        $wpdb->show_errors();
        $errors = array();

        // Step 1: Add unit costs to order items from current product costs
        $step1 = $wpdb->query( "
            INSERT INTO {$wpdb->prefix}woocommerce_order_itemmeta (order_item_id, meta_key, meta_value)
            SELECT oi.order_item_id, '_spvs_unit_cost', COALESCE(pm.meta_value, '0')
            FROM {$wpdb->prefix}woocommerce_order_items oi
            INNER JOIN {$wpdb->prefix}woocommerce_order_itemmeta oim_product
                ON oi.order_item_id = oim_product.order_item_id
                AND oim_product.meta_key = '_product_id'
            LEFT JOIN {$wpdb->postmeta} pm
                ON oim_product.meta_value = pm.post_id
                AND pm.meta_key = '_spvs_cost_price'
            WHERE oi.order_item_type = 'line_item'
            ON DUPLICATE KEY UPDATE meta_value = VALUES(meta_value)
        " );

        if ( $step1 === false ) {
            $errors[] = 'Step 1 (unit costs) failed: ' . $wpdb->last_error;
        }

        usleep( 100000 ); // Rate limiting

        // Step 2: Calculate line profit for each order item
        $step2 = $wpdb->query( "
            INSERT INTO {$wpdb->prefix}woocommerce_order_itemmeta (order_item_id, meta_key, meta_value)
            SELECT oi.order_item_id, '_spvs_line_profit',
                ROUND(COALESCE(oim_total.meta_value, 0) -
                      (COALESCE(oim_cost.meta_value, 0) * COALESCE(oim_qty.meta_value, 0)), 2)
            FROM {$wpdb->prefix}woocommerce_order_items oi
            LEFT JOIN {$wpdb->prefix}woocommerce_order_itemmeta oim_total
                ON oi.order_item_id = oim_total.order_item_id
                AND oim_total.meta_key = '_line_total'
            LEFT JOIN {$wpdb->prefix}woocommerce_order_itemmeta oim_cost
                ON oi.order_item_id = oim_cost.order_item_id
                AND oim_cost.meta_key = '_spvs_unit_cost'
            LEFT JOIN {$wpdb->prefix}woocommerce_order_itemmeta oim_qty
                ON oi.order_item_id = oim_qty.order_item_id
                AND oim_qty.meta_key = '_qty'
            WHERE oi.order_item_type = 'line_item'
            ON DUPLICATE KEY UPDATE meta_value = VALUES(meta_value)
        " );

        if ( $step2 === false ) {
            $errors[] = 'Step 2 (line profit) failed: ' . $wpdb->last_error;
        }

        usleep( 100000 ); // Rate limiting

        // Step 3: Calculate total profit per order
        // Check if HPOS is enabled
        $orders_table = $wpdb->prefix . 'wc_orders';
        $hpos_enabled = $wpdb->get_var( "SHOW TABLES LIKE '{$orders_table}'" ) === $orders_table;

        if ( $hpos_enabled ) {
            // Use HPOS table
            $step3 = $wpdb->query( "
                INSERT INTO {$wpdb->prefix}wc_orders_meta (order_id, meta_key, meta_value)
                SELECT oi.order_id, '_spvs_total_profit',
                    ROUND(SUM(COALESCE(oim_profit.meta_value, 0)), 2)
                FROM {$wpdb->prefix}woocommerce_order_items oi
                LEFT JOIN {$wpdb->prefix}woocommerce_order_itemmeta oim_profit
                    ON oi.order_item_id = oim_profit.order_item_id
                    AND oim_profit.meta_key = '_spvs_line_profit'
                WHERE oi.order_item_type = 'line_item'
                GROUP BY oi.order_id
                ON DUPLICATE KEY UPDATE meta_value = VALUES(meta_value)
            " );
        } else {
            // Use legacy postmeta table
            $step3 = $wpdb->query( "
                INSERT INTO {$wpdb->postmeta} (post_id, meta_key, meta_value)
                SELECT oi.order_id, '_spvs_total_profit',
                    ROUND(SUM(COALESCE(oim_profit.meta_value, 0)), 2)
                FROM {$wpdb->prefix}woocommerce_order_items oi
                LEFT JOIN {$wpdb->prefix}woocommerce_order_itemmeta oim_profit
                    ON oi.order_item_id = oim_profit.order_item_id
                    AND oim_profit.meta_key = '_spvs_line_profit'
                WHERE oi.order_item_type = 'line_item'
                GROUP BY oi.order_id
                ON DUPLICATE KEY UPDATE meta_value = VALUES(meta_value)
            " );
        }

        if ( $step3 === false ) {
            $errors[] = 'Step 3 (order totals) failed: ' . $wpdb->last_error;
        }

        // Count products with costs
        $products_with_costs = $wpdb->get_var( $wpdb->prepare( "
            SELECT COUNT(DISTINCT pm.post_id)
            FROM {$wpdb->postmeta} pm
            INNER JOIN {$wpdb->posts} p ON pm.post_id = p.ID
            WHERE pm.meta_key = %s
            AND pm.meta_value != ''
            AND pm.meta_value != '0'
            AND p.post_type IN ('product', 'product_variation')
        ", self::PRODUCT_COST_META ) );

        // Build result message
        if ( ! empty( $errors ) ) {
            $msg = 'profit_recalc_error:' . implode( ' | ', $errors );
        } else {
            $total_affected = $step1 !== false ? $step1 : 0;
            $msg = sprintf( 'profit_recalc_done:%d:%d', $total_affected, $products_with_costs );
        }

        wp_safe_redirect( add_query_arg( array(
            'page' => 'spvs-dashboard',
            'tab' => 'health',
            'spvs_msg' => rawurlencode( $msg )
        ), admin_url( 'admin.php' ) ) );
        exit;
    }

    /**
     * AJAX: Get total count of order items for recalculation
     */
    public function ajax_get_recalc_count() {
        check_ajax_referer( 'spvs_recalc_profit', 'nonce' );

        if ( ! current_user_can( 'manage_woocommerce' ) ) {
            wp_send_json_error( array( 'message' => __( 'Insufficient permissions.', 'spvs-cost-profit' ) ) );
        }

        global $wpdb;

        // Get total count of order items
        $total_items = $wpdb->get_var( "
            SELECT COUNT(*)
            FROM {$wpdb->prefix}woocommerce_order_items oi
            WHERE oi.order_item_type = 'line_item'
        " );

        // Get products with costs
        $products_with_costs = $wpdb->get_var( $wpdb->prepare( "
            SELECT COUNT(DISTINCT pm.post_id)
            FROM {$wpdb->postmeta} pm
            INNER JOIN {$wpdb->posts} p ON pm.post_id = p.ID
            WHERE pm.meta_key = %s
            AND pm.meta_value != ''
            AND pm.meta_value != '0'
            AND p.post_type IN ('product', 'product_variation')
        ", self::PRODUCT_COST_META ) );

        wp_send_json_success( array(
            'total' => (int) $total_items,
            'products_with_costs' => (int) $products_with_costs,
        ) );
    }

    /**
     * AJAX: Process a batch of order items for profit recalculation
     */
    public function ajax_recalc_batch() {
        check_ajax_referer( 'spvs_recalc_profit', 'nonce' );

        if ( ! current_user_can( 'manage_woocommerce' ) ) {
            wp_send_json_error( array( 'message' => __( 'Insufficient permissions.', 'spvs-cost-profit' ) ) );
        }

        global $wpdb;

        $offset = isset( $_POST['offset'] ) ? absint( $_POST['offset'] ) : 0;
        $batch_size = 100; // Process 100 items at a time

        // Step 1: Add unit costs to order items (batch)
        $step1 = $wpdb->query( $wpdb->prepare( "
            INSERT INTO {$wpdb->prefix}woocommerce_order_itemmeta (order_item_id, meta_key, meta_value)
            SELECT oi.order_item_id, '_spvs_unit_cost', COALESCE(pm.meta_value, '0')
            FROM {$wpdb->prefix}woocommerce_order_items oi
            INNER JOIN {$wpdb->prefix}woocommerce_order_itemmeta oim_product
                ON oi.order_item_id = oim_product.order_item_id
                AND oim_product.meta_key = '_product_id'
            LEFT JOIN {$wpdb->postmeta} pm
                ON oim_product.meta_value = pm.post_id
                AND pm.meta_key = '_spvs_cost_price'
            WHERE oi.order_item_type = 'line_item'
            LIMIT %d OFFSET %d
            ON DUPLICATE KEY UPDATE meta_value = VALUES(meta_value)
        ", $batch_size, $offset ) );

        // Step 2: Calculate line profit (batch)
        $wpdb->query( $wpdb->prepare( "
            INSERT INTO {$wpdb->prefix}woocommerce_order_itemmeta (order_item_id, meta_key, meta_value)
            SELECT oi.order_item_id, '_spvs_line_profit',
                ROUND(COALESCE(oim_total.meta_value, 0) -
                      (COALESCE(oim_cost.meta_value, 0) * COALESCE(oim_qty.meta_value, 0)), 2)
            FROM {$wpdb->prefix}woocommerce_order_items oi
            LEFT JOIN {$wpdb->prefix}woocommerce_order_itemmeta oim_total
                ON oi.order_item_id = oim_total.order_item_id
                AND oim_total.meta_key = '_line_total'
            LEFT JOIN {$wpdb->prefix}woocommerce_order_itemmeta oim_cost
                ON oi.order_item_id = oim_cost.order_item_id
                AND oim_cost.meta_key = '_spvs_unit_cost'
            LEFT JOIN {$wpdb->prefix}woocommerce_order_itemmeta oim_qty
                ON oi.order_item_id = oim_qty.order_item_id
                AND oim_qty.meta_key = '_qty'
            WHERE oi.order_item_type = 'line_item'
            LIMIT %d OFFSET %d
            ON DUPLICATE KEY UPDATE meta_value = VALUES(meta_value)
        ", $batch_size, $offset ) );

        // Get affected order IDs from this batch
        $order_ids = $wpdb->get_col( $wpdb->prepare( "
            SELECT DISTINCT oi.order_id
            FROM {$wpdb->prefix}woocommerce_order_items oi
            WHERE oi.order_item_type = 'line_item'
            LIMIT %d OFFSET %d
        ", $batch_size, $offset ) );

        // Step 3: Update order totals for affected orders
        if ( ! empty( $order_ids ) ) {
            $order_ids_list = implode( ',', array_map( 'absint', $order_ids ) );

            // Check if HPOS is enabled
            $orders_table = $wpdb->prefix . 'wc_orders';
            $hpos_enabled = $wpdb->get_var( "SHOW TABLES LIKE '{$orders_table}'" ) === $orders_table;

            if ( $hpos_enabled ) {
                $wpdb->query( "
                    INSERT INTO {$wpdb->prefix}wc_orders_meta (order_id, meta_key, meta_value)
                    SELECT oi.order_id, '_spvs_total_profit',
                        ROUND(SUM(COALESCE(oim_profit.meta_value, 0)), 2)
                    FROM {$wpdb->prefix}woocommerce_order_items oi
                    LEFT JOIN {$wpdb->prefix}woocommerce_order_itemmeta oim_profit
                        ON oi.order_item_id = oim_profit.order_item_id
                        AND oim_profit.meta_key = '_spvs_line_profit'
                    WHERE oi.order_item_type = 'line_item'
                    AND oi.order_id IN ({$order_ids_list})
                    GROUP BY oi.order_id
                    ON DUPLICATE KEY UPDATE meta_value = VALUES(meta_value)
                " );
            } else {
                $wpdb->query( "
                    INSERT INTO {$wpdb->postmeta} (post_id, meta_key, meta_value)
                    SELECT oi.order_id, '_spvs_total_profit',
                        ROUND(SUM(COALESCE(oim_profit.meta_value, 0)), 2)
                    FROM {$wpdb->prefix}woocommerce_order_items oi
                    LEFT JOIN {$wpdb->prefix}woocommerce_order_itemmeta oim_profit
                        ON oi.order_item_id = oim_profit.order_item_id
                        AND oim_profit.meta_key = '_spvs_line_profit'
                    WHERE oi.order_item_type = 'line_item'
                    AND oi.order_id IN ({$order_ids_list})
                    GROUP BY oi.order_id
                    ON DUPLICATE KEY UPDATE meta_value = VALUES(meta_value)
                " );
            }
        }

        $processed = $step1 !== false ? $step1 : 0;

        wp_send_json_success( array(
            'processed' => $processed,
            'orders_updated' => count( $order_ids ),
        ) );
    }

    public function download_missing_cost_csv() {
        if ( ! current_user_can( 'read' ) ) wp_die( esc_html__( 'Insufficient permissions.', 'spvs-cost-profit' ) );
        header( 'Content-Type: text/csv; charset=utf-8' );
        header( 'Content-Disposition: attachment; filename=spvs-missing-cost-with-qty.csv' );
        $out = fopen( 'php://output', 'w' );
        fputcsv( $out, array( 'product_id', 'parent_id', 'type', 'status', 'sku', 'name', 'qty', 'regular_price' ) );

        $batch_size = 500; $paged = 1;
        while ( true ) {
            $q = new WP_Query( array(
                'post_type'      => array( 'product', 'product_variation' ),
                'post_status'    => 'publish',
                'posts_per_page' => $batch_size,
                'paged'          => $paged,
                'fields'         => 'ids',
                'no_found_rows'  => true,
            ) );
            if ( ! $q->have_posts() ) break;
            foreach ( $q->posts as $pid ) {
                $product = wc_get_product( $pid ); if ( ! $product ) continue;
                $qty = $product->managing_stock() ? (int) $product->get_stock_quantity() : 0;
                if ( $qty > 0 ) {
                    $cost = (float) $this->get_product_cost( $pid );
                    if ( $cost <= 0 ) {
                        fputcsv( $out, array(
                            $pid,
                            $product->is_type('variation') ? $product->get_parent_id() : '',
                            $product->get_type(),
                            $product->get_status(),
                            $product->get_sku(),
                            $product->get_formatted_name(),
                            $qty,
                            (float) $product->get_regular_price(),
                        ) );
                    }
                }
            }
            $paged++; usleep(150000);
        }
        fclose( $out ); exit;
    }

    public function export_inventory_csv() {
        if ( ! current_user_can( 'read' ) ) wp_die( esc_html__( 'Insufficient permissions.', 'spvs-cost-profit' ) );
        check_admin_referer( 'spvs_export_inventory_csv' );

        $available = $this->spvs_get_available_columns();
        $selected = isset( $_GET['spvs_cols'] ) ? array_map( 'sanitize_text_field', (array) $_GET['spvs_cols'] ) : array( 'sku', 'name', 'qty', 'cost', 'regular_price' );
        $selected = array_values( array_intersect( array_keys( $available ), $selected ) );
        if ( empty( $selected ) ) $selected = array( 'sku', 'name', 'qty', 'cost', 'regular_price' );

        $filename = 'inventory-value-' . date( 'Ymd-His' ) . '.csv';
        header( 'Content-Type: text/csv; charset=utf-8' );
        header( 'Content-Disposition: attachment; filename=' . $filename );
        $out = fopen( 'php://output', 'w' );

        $header = array(); foreach ( $selected as $key ) { $header[] = $available[ $key ]; }
        fputcsv( $out, $header );

        $batch_size = 500; $paged = 1;
        while ( true ) {
            $q = new WP_Query( array( 'post_type' => array( 'product', 'product_variation' ), 'post_status' => 'publish', 'posts_per_page' => $batch_size, 'paged' => $paged, 'fields' => 'ids', 'no_found_rows' => true ) );
            if ( ! $q->have_posts() ) break;
            foreach ( $q->posts as $pid ) {
                $product = wc_get_product( $pid ); if ( ! $product ) continue;
                $row = $this->spvs_build_row_for_columns( $product, $selected );
                $row = array_map( function( $v ) { if ( is_array( $v ) ) return implode( ', ', $v ); if ( is_bool( $v ) ) return $v ? 'true' : 'false'; return (string) $v; }, $row );
                fputcsv( $out, $row );
            }
            $paged++; usleep(150000);
        }
        fclose( $out ); exit;
    }
}

/** Activation requirements check */
register_activation_hook( __FILE__, function() {
    if ( version_compare( PHP_VERSION, '7.4', '<' ) ) { deactivate_plugins( plugin_basename( __FILE__ ) ); wp_die( esc_html__( 'SPVS Cost & Profit requires PHP 7.4 or higher.', 'spvs-cost-profit' ) ); }
    if ( ! class_exists( 'WooCommerce' ) ) { deactivate_plugins( plugin_basename( __FILE__ ) ); wp_die( esc_html__( 'SPVS Cost & Profit requires WooCommerce to be active.', 'spvs-cost-profit' ) ); }
} );

// Deactivation: clear cron/transient (leave data intact until uninstall)
register_deactivation_hook( __FILE__, function() {
    $ts = wp_next_scheduled( 'spvs_daily_inventory_recalc' );
    if ( $ts ) { wp_unschedule_event( $ts, 'spvs_daily_inventory_recalc' ); }
    delete_transient( SPVS_Cost_Profit::RECALC_LOCK_TRANSIENT );
} );

// Bootstrap
SPVS_Cost_Profit::instance();

endif;
