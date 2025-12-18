<?php
/**
 * Plugin Name: SPVS Cost & Profit for WooCommerce
 * Description: Track product costs and calculate Total Cost of Products (TCOP) and Total Retail Value (TRV) for inventory.
 * Version: 2.0.3
 * Author: Megatron
 * License: GPL-2.0+
 * License URI: https://www.gnu.org/licenses/gpl-2.0.txt
 * Text Domain: spvs-cost-profit
 * Requires at least: 6.0
 * Requires PHP: 7.4
 * WC requires at least: 7.0
 * WC tested up to: 9.1
 */

if ( ! defined( 'ABSPATH' ) ) exit;

if ( ! class_exists( 'SPVS_Cost_Profit' ) ) :

final class SPVS_Cost_Profit {

    const PRODUCT_COST_META         = '_spvs_cost_price';
    const INVENTORY_TOTALS_OPTION   = 'spvs_inventory_totals';
    const RECALC_LOCK_TRANSIENT     = 'spvs_recalc_lock';

    private static $instance = null;

    public static function instance() {
        if ( null === self::$instance ) {
            self::$instance = new self();
        }
        return self::$instance;
    }

    private function __construct() {
        add_action( 'init', array( $this, 'init' ), 20 );
        add_action( 'before_woocommerce_init', array( $this, 'declare_hpos_compat' ) );
    }

    public function declare_hpos_compat() {
        if ( class_exists( '\Automattic\WooCommerce\Utilities\FeaturesUtil' ) ) {
            \Automattic\WooCommerce\Utilities\FeaturesUtil::declare_compatibility( 'custom_order_tables', __FILE__, true );
        }
    }

    public function init() {
        if ( ! class_exists( 'WooCommerce' ) ) return;

        // Product cost fields
        add_action( 'woocommerce_product_options_pricing', array( $this, 'add_product_cost_field' ) );
        add_action( 'woocommerce_admin_process_product_object', array( $this, 'save_product_cost_field' ) );
        add_action( 'woocommerce_variation_options_pricing', array( $this, 'add_variation_cost_field' ), 10, 3 );
        add_action( 'woocommerce_save_product_variation', array( $this, 'save_variation_cost_field' ), 10, 2 );

        // Admin page
        add_action( 'admin_menu', array( $this, 'register_admin_page' ) );

        // TCOP bar on orders screen
        add_action( 'in_admin_header', array( $this, 'render_tcop_bar' ) );

        // Admin actions
        add_action( 'admin_post_spvs_recalculate', array( $this, 'handle_recalculate' ) );
        add_action( 'admin_post_spvs_import_costs', array( $this, 'handle_import_costs' ) );
        add_action( 'admin_post_spvs_export_costs', array( $this, 'handle_export_costs' ) );

        // Daily cron
        add_action( 'init', array( $this, 'schedule_daily_cron' ) );
        add_action( 'spvs_daily_recalc', array( $this, 'recalculate_totals' ) );
    }

    // ============ Product Cost Fields ============

    public function add_product_cost_field() {
        global $thepostid;
        $pid = $thepostid ? $thepostid : get_the_ID();
        echo '<div class="options_group">';
        woocommerce_wp_text_input( array(
            'id'                => self::PRODUCT_COST_META,
            'label'             => __( 'Cost Price', 'spvs-cost-profit' ),
            'desc_tip'          => true,
            'description'       => __( 'Your unit cost for this product.', 'spvs-cost-profit' ),
            'type'              => 'number',
            'custom_attributes' => array( 'step' => '0.01', 'min' => '0' ),
            'data_type'         => 'price',
            'value'             => wc_format_localized_price( $this->get_cost_raw( $pid ) ),
        ) );
        echo '</div>';
    }

    public function save_product_cost_field( $product ) {
        if ( ! $product instanceof WC_Product ) return;
        $raw = isset( $_POST[ self::PRODUCT_COST_META ] ) ? wp_unslash( $_POST[ self::PRODUCT_COST_META ] ) : '';
        $value = $raw !== '' ? wc_format_decimal( wc_clean( $raw ) ) : '';

        if ( $value === '' ) {
            $product->delete_meta_data( self::PRODUCT_COST_META );
        } else {
            $product->update_meta_data( self::PRODUCT_COST_META, $value );
        }
        $product->save();
    }

    public function add_variation_cost_field( $loop, $variation_data, $variation ) {
        $variation_id = is_object( $variation ) && isset( $variation->ID ) ? $variation->ID : (int) $variation;
        $value = wc_format_localized_price( $this->get_cost_raw( $variation_id ) );

        echo '<div>';
        woocommerce_wp_text_input( array(
            'id'                => self::PRODUCT_COST_META . '[' . $loop . ']',
            'name'              => self::PRODUCT_COST_META . '[' . $loop . ']',
            'label'             => __( 'Cost Price', 'spvs-cost-profit' ),
            'desc_tip'          => true,
            'description'       => __( 'Your unit cost for this variation. Leave empty to use parent cost.', 'spvs-cost-profit' ),
            'type'              => 'number',
            'custom_attributes' => array( 'step' => '0.01', 'min' => '0' ),
            'data_type'         => 'price',
            'value'             => $value,
            'wrapper_class'     => 'form-row form-row-full',
        ) );
        echo '</div>';
    }

    public function save_variation_cost_field( $variation_id, $i ) {
        if ( ! isset( $_POST[ self::PRODUCT_COST_META ] ) || ! is_array( $_POST[ self::PRODUCT_COST_META ] ) ) return;
        $raw = isset( $_POST[ self::PRODUCT_COST_META ][ $i ] ) ? wp_unslash( $_POST[ self::PRODUCT_COST_META ][ $i ] ) : '';
        $value = $raw !== '' ? wc_format_decimal( wc_clean( $raw ) ) : '';

        if ( $value === '' ) {
            delete_post_meta( $variation_id, self::PRODUCT_COST_META );
        } else {
            update_post_meta( $variation_id, self::PRODUCT_COST_META, $value );
        }
    }

    private function get_cost_raw( $product_id ) {
        $value = get_post_meta( $product_id, self::PRODUCT_COST_META, true );
        return $value !== '' ? $value : '';
    }

    private function get_cost( $product_id ) {
        $value = $this->get_cost_raw( $product_id );

        // If variation has no cost, inherit from parent
        if ( $value === '' ) {
            $product = wc_get_product( $product_id );
            if ( $product && $product->is_type( 'variation' ) ) {
                $parent_id = $product->get_parent_id();
                if ( $parent_id ) {
                    $value = $this->get_cost_raw( $parent_id );
                }
            }
        }

        return $value !== '' ? (float) $value : 0.0;
    }

    // ============ Inventory Totals Calculation ============

    public function recalculate_totals() {
        if ( get_transient( self::RECALC_LOCK_TRANSIENT ) ) return;
        set_transient( self::RECALC_LOCK_TRANSIENT, 1, MINUTE_IN_SECONDS );

        $tcop = 0.0;
        $trv = 0.0;
        $count = 0;

        $args = array(
            'post_type'      => array( 'product', 'product_variation' ),
            'post_status'    => 'publish',
            'posts_per_page' => -1,
            'fields'         => 'ids',
        );

        $products = get_posts( $args );

        foreach ( $products as $product_id ) {
            $product = wc_get_product( $product_id );
            if ( ! $product ) continue;

            // Only include products that manage stock
            if ( ! $product->managing_stock() ) continue;

            $qty = (int) $product->get_stock_quantity();
            if ( $qty <= 0 ) continue;

            $cost = $this->get_cost( $product_id );
            if ( $cost <= 0 ) continue;

            $price = (float) $product->get_regular_price();
            if ( $price <= 0 ) continue;

            // Product qualifies: has stock, cost, and price
            $tcop += $cost * $qty;
            $trv += $price * $qty;
            $count++;
        }

        update_option( self::INVENTORY_TOTALS_OPTION, array(
            'tcop'    => $tcop,
            'trv'     => $trv,
            'count'   => $count,
            'updated' => time(),
        ), false );

        delete_transient( self::RECALC_LOCK_TRANSIENT );
    }

    // ============ TCOP Bar ============

    public function render_tcop_bar() {
        $screen = get_current_screen();
        if ( ! $screen ) return;

        // Show on WooCommerce orders pages (both classic and HPOS)
        $show = in_array( $screen->id, array( 'edit-shop_order', 'woocommerce_page_wc-orders', 'shop_order' ), true );
        if ( ! $show ) return;

        $totals = get_option( self::INVENTORY_TOTALS_OPTION, array() );
        $tcop = isset( $totals['tcop'] ) ? $totals['tcop'] : 0;
        $trv = isset( $totals['trv'] ) ? $totals['trv'] : 0;
        $spread = $trv - $tcop;
        $updated = isset( $totals['updated'] ) ? $totals['updated'] : 0;

        ?>
        <div style="background: #fff; border-left: 4px solid #5b32d1; padding: 24px; margin: 0 20px 20px 0; box-shadow: 0 1px 4px rgba(0,0,0,0.08); position: relative; z-index: 1000; overflow: visible;">
            <div style="display: flex; align-items: flex-start; justify-content: space-between; gap: 40px; flex-wrap: wrap;">

                <div style="display: flex; gap: 50px; align-items: flex-start; flex-wrap: wrap;">
                    <div>
                        <div style="font-size: 10px; font-weight: 600; color: #666; text-transform: uppercase; letter-spacing: 1px; margin-bottom: 8px;">TOTAL COST</div>
                        <div style="font-size: 26px; font-weight: 700; color: #2c3e50; line-height: 1;"><?php echo wc_price( $tcop ); ?></div>
                    </div>

                    <div style="width: 1px; height: 50px; background: #e0e0e0; align-self: center;"></div>

                    <div>
                        <div style="font-size: 10px; font-weight: 600; color: #666; text-transform: uppercase; letter-spacing: 1px; margin-bottom: 8px;">RETAIL VALUE</div>
                        <div style="font-size: 26px; font-weight: 700; color: #27ae60; line-height: 1;"><?php echo wc_price( $trv ); ?></div>
                    </div>

                    <div style="width: 1px; height: 50px; background: #e0e0e0; align-self: center;"></div>

                    <div>
                        <div style="font-size: 10px; font-weight: 600; color: #666; text-transform: uppercase; letter-spacing: 1px; margin-bottom: 8px;">SPREAD</div>
                        <div style="font-size: 26px; font-weight: 700; color: <?php echo $spread >= 0 ? '#27ae60' : '#e74c3c'; ?>; line-height: 1;">
                            <?php echo wc_price( $spread ); ?>
                        </div>
                    </div>
                </div>

                <div style="font-size: 11px; color: #999; font-style: italic; padding-top: 12px;">
                    <?php if ( $updated ) : ?>
                        <span style="opacity: 0.7;">⟳</span> <?php echo human_time_diff( $updated, time() ); ?> ago
                    <?php endif; ?>
                </div>
            </div>
        </div>
        <?php
    }

    // ============ Admin Page ============

    public function register_admin_page() {
        add_submenu_page(
            'woocommerce',
            __( 'SPVS Inventory Costs', 'spvs-cost-profit' ),
            __( 'Inventory Costs', 'spvs-cost-profit' ),
            'manage_woocommerce',
            'spvs-inventory-costs',
            array( $this, 'render_admin_page' )
        );
    }

    public function render_admin_page() {
        if ( ! current_user_can( 'manage_woocommerce' ) ) {
            wp_die( __( 'Insufficient permissions.', 'spvs-cost-profit' ) );
        }

        $totals = get_option( self::INVENTORY_TOTALS_OPTION, array() );
        $tcop = isset( $totals['tcop'] ) ? $totals['tcop'] : 0;
        $trv = isset( $totals['trv'] ) ? $totals['trv'] : 0;
        $count = isset( $totals['count'] ) ? $totals['count'] : 0;
        $updated = isset( $totals['updated'] ) ? $totals['updated'] : 0;
        $spread = $trv - $tcop;

        ?>
        <div class="wrap">
            <h1><?php _e( 'SPVS Inventory Costs', 'spvs-cost-profit' ); ?></h1>

            <div style="display: flex; gap: 20px; margin: 20px 0; flex-wrap: wrap;">

                <div style="flex: 1; min-width: 250px; background: #fff; padding: 20px; border-left: 4px solid #2271b1; box-shadow: 0 1px 3px rgba(0,0,0,0.1);">
                    <h3 style="margin: 0 0 10px 0; color: #666;"><?php _e( 'TCOP (Total Cost)', 'spvs-cost-profit' ); ?></h3>
                    <p style="font-size: 28px; font-weight: bold; margin: 0; color: #2271b1;"><?php echo wc_price( $tcop ); ?></p>
                </div>

                <div style="flex: 1; min-width: 250px; background: #fff; padding: 20px; border-left: 4px solid #00a32a; box-shadow: 0 1px 3px rgba(0,0,0,0.1);">
                    <h3 style="margin: 0 0 10px 0; color: #666;"><?php _e( 'TRV (Total Retail Value)', 'spvs-cost-profit' ); ?></h3>
                    <p style="font-size: 28px; font-weight: bold; margin: 0; color: #00a32a;"><?php echo wc_price( $trv ); ?></p>
                </div>

                <div style="flex: 1; min-width: 250px; background: #fff; padding: 20px; border-left: 4px solid #d63638; box-shadow: 0 1px 3px rgba(0,0,0,0.1);">
                    <h3 style="margin: 0 0 10px 0; color: #666;"><?php _e( 'Spread', 'spvs-cost-profit' ); ?></h3>
                    <p style="font-size: 28px; font-weight: bold; margin: 0; color: <?php echo $spread >= 0 ? '#00a32a' : '#d63638'; ?>;"><?php echo wc_price( $spread ); ?></p>
                </div>

            </div>

            <div style="background: #fff; padding: 15px; margin: 20px 0; box-shadow: 0 1px 3px rgba(0,0,0,0.1);">
                <p>
                    <strong><?php _e( 'Products counted:', 'spvs-cost-profit' ); ?></strong> <?php echo $count; ?><br>
                    <?php if ( $updated ) : ?>
                        <small><?php echo sprintf( __( 'Last updated: %s ago', 'spvs-cost-profit' ), human_time_diff( $updated, time() ) ); ?></small>
                    <?php endif; ?>
                </p>
                <p>
                    <small><?php _e( 'Only products with stock > 0, cost > 0, and price > 0 are counted.', 'spvs-cost-profit' ); ?></small>
                </p>
            </div>

            <p>
                <a href="<?php echo esc_url( wp_nonce_url( admin_url( 'admin-post.php?action=spvs_recalculate' ), 'spvs_recalculate' ) ); ?>" class="button button-primary">
                    <?php _e( 'Recalculate Now', 'spvs-cost-profit' ); ?>
                </a>
            </p>

            <hr style="margin: 30px 0;">

            <h2><?php _e( 'Import Costs (CSV)', 'spvs-cost-profit' ); ?></h2>
            <form method="post" action="<?php echo esc_url( admin_url( 'admin-post.php' ) ); ?>" enctype="multipart/form-data">
                <input type="hidden" name="action" value="spvs_import_costs">
                <?php wp_nonce_field( 'spvs_import_costs' ); ?>
                <p>
                    <input type="file" name="csv_file" accept=".csv" required>
                    <button type="submit" class="button"><?php _e( 'Import', 'spvs-cost-profit' ); ?></button>
                </p>
                <p class="description">
                    <?php _e( 'CSV format: sku,cost OR product_id,cost (with header row)', 'spvs-cost-profit' ); ?>
                </p>
            </form>

            <h2><?php _e( 'Export Costs (CSV)', 'spvs-cost-profit' ); ?></h2>
            <p>
                <a href="<?php echo esc_url( wp_nonce_url( admin_url( 'admin-post.php?action=spvs_export_costs' ), 'spvs_export_costs' ) ); ?>" class="button">
                    <?php _e( 'Export All Product Costs', 'spvs-cost-profit' ); ?>
                </a>
            </p>

        </div>
        <?php
    }

    // ============ Admin Actions ============

    public function handle_recalculate() {
        check_admin_referer( 'spvs_recalculate' );
        if ( ! current_user_can( 'manage_woocommerce' ) ) {
            wp_die( __( 'Insufficient permissions.', 'spvs-cost-profit' ) );
        }

        $this->recalculate_totals();

        wp_safe_redirect( admin_url( 'admin.php?page=spvs-inventory-costs&recalculated=1' ) );
        exit;
    }

    public function handle_import_costs() {
        check_admin_referer( 'spvs_import_costs' );
        if ( ! current_user_can( 'manage_woocommerce' ) ) {
            wp_die( __( 'Insufficient permissions.', 'spvs-cost-profit' ) );
        }

        if ( empty( $_FILES['csv_file']['tmp_name'] ) ) {
            wp_die( __( 'No file uploaded.', 'spvs-cost-profit' ) );
        }

        $file = $_FILES['csv_file']['tmp_name'];
        $handle = fopen( $file, 'r' );
        if ( ! $handle ) {
            wp_die( __( 'Could not read file.', 'spvs-cost-profit' ) );
        }

        $header = fgetcsv( $handle );
        if ( ! $header ) {
            fclose( $handle );
            wp_die( __( 'Invalid CSV file.', 'spvs-cost-profit' ) );
        }

        $header = array_map( 'strtolower', array_map( 'trim', $header ) );
        $sku_col = array_search( 'sku', $header );
        $id_col = array_search( 'product_id', $header );
        $cost_col = array_search( 'cost', $header );

        if ( $cost_col === false || ( $sku_col === false && $id_col === false ) ) {
            fclose( $handle );
            wp_die( __( 'CSV must have "sku" or "product_id" column and "cost" column.', 'spvs-cost-profit' ) );
        }

        $updated = 0;
        while ( ( $row = fgetcsv( $handle ) ) !== false ) {
            $product_id = null;

            if ( $sku_col !== false && ! empty( $row[ $sku_col ] ) ) {
                $product_id = wc_get_product_id_by_sku( trim( $row[ $sku_col ] ) );
            } elseif ( $id_col !== false && ! empty( $row[ $id_col ] ) ) {
                $product_id = (int) $row[ $id_col ];
            }

            if ( ! $product_id ) continue;

            $cost = isset( $row[ $cost_col ] ) ? wc_format_decimal( trim( $row[ $cost_col ] ) ) : '';
            if ( $cost === '' ) continue;

            update_post_meta( $product_id, self::PRODUCT_COST_META, $cost );
            $updated++;
        }

        fclose( $handle );

        $this->recalculate_totals();

        wp_safe_redirect( admin_url( 'admin.php?page=spvs-inventory-costs&imported=' . $updated ) );
        exit;
    }

    public function handle_export_costs() {
        check_admin_referer( 'spvs_export_costs' );
        if ( ! current_user_can( 'manage_woocommerce' ) ) {
            wp_die( __( 'Insufficient permissions.', 'spvs-cost-profit' ) );
        }

        $args = array(
            'post_type'      => array( 'product', 'product_variation' ),
            'post_status'    => 'publish',
            'posts_per_page' => -1,
            'fields'         => 'ids',
        );

        $products = get_posts( $args );

        header( 'Content-Type: text/csv' );
        header( 'Content-Disposition: attachment; filename="product-costs-' . date( 'Y-m-d' ) . '.csv"' );

        $out = fopen( 'php://output', 'w' );
        fputcsv( $out, array( 'product_id', 'sku', 'name', 'type', 'cost' ) );

        foreach ( $products as $product_id ) {
            $product = wc_get_product( $product_id );
            if ( ! $product ) continue;

            $cost = $this->get_cost_raw( $product_id );

            fputcsv( $out, array(
                $product_id,
                $product->get_sku(),
                $product->get_name(),
                $product->get_type(),
                $cost,
            ) );
        }

        fclose( $out );
        exit;
    }

    // ============ Daily Cron ============

    public function schedule_daily_cron() {
        if ( ! wp_next_scheduled( 'spvs_daily_recalc' ) ) {
            wp_schedule_event( time(), 'daily', 'spvs_daily_recalc' );
        }
    }
}

endif;

// Initialize
add_action( 'plugins_loaded', array( 'SPVS_Cost_Profit', 'instance' ) );

// Uninstall hook
register_uninstall_hook( __FILE__, 'spvs_cost_profit_uninstall' );

function spvs_cost_profit_uninstall() {
    delete_option( 'spvs_inventory_totals' );
    delete_transient( 'spvs_recalc_lock' );

    $timestamp = wp_next_scheduled( 'spvs_daily_recalc' );
    if ( $timestamp ) {
        wp_unschedule_event( $timestamp, 'spvs_daily_recalc' );
    }
}
