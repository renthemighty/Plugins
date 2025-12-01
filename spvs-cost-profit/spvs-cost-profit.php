<?php
/**
 * Plugin Name: SPVS Cost & Profit for WooCommerce
 * Description: Adds product cost, computes profit per order, TCOP/Retail inventory totals with CSV export/import, monthly profit reports, and a dedicated admin page.
 * Version: 1.5.3
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

    // Data backup & protection
    const BACKUP_OPTION_PREFIX      = 'spvs_cost_backup_';
    const BACKUP_LATEST_OPTION      = 'spvs_cost_backup_latest';
    const BACKUP_COUNT_OPTION       = 'spvs_cost_backup_count';
    const MAX_BACKUPS               = 2; // Keep 2 days of backups

    private static $instance = null;

    public static function instance() {
        if ( null === self::$instance ) { self::$instance = new self(); }
        return self::$instance;
    }

    private function __construct() {
        add_action( 'init', array( $this, 'maybe_init' ), 20 );
        add_action( 'before_woocommerce_init', array( $this, 'declare_hpos_compat' ) );
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

        /** Monthly profit report export */
        add_action( 'admin_post_spvs_export_monthly_profit', array( $this, 'export_monthly_profit_csv' ) );

        /** Daily cron for inventory totals */
        add_action( 'init', array( $this, 'maybe_schedule_daily_cron' ) );
        add_action( 'spvs_daily_inventory_recalc', array( $this, 'recalculate_inventory_totals' ) );

        /** Data backup & protection */
        add_action( 'init', array( $this, 'maybe_schedule_backup_cron' ) );
        add_action( 'spvs_daily_cost_backup', array( $this, 'create_cost_data_backup' ) );
        add_action( 'admin_post_spvs_backup_costs_now', array( $this, 'handle_manual_backup' ) );
        add_action( 'admin_post_spvs_restore_costs', array( $this, 'handle_restore_costs' ) );
        add_action( 'admin_post_spvs_export_backup', array( $this, 'export_backup_data' ) );

        /** Cost of Goods import */
        add_action( 'admin_post_spvs_import_from_cog', array( $this, 'import_from_cost_of_goods' ) );
        add_action( 'wp_ajax_spvs_cog_import_batch', array( $this, 'ajax_import_cog_batch' ) );

        /** Order profit recalculation */
        add_action( 'wp_ajax_spvs_recalc_orders_batch', array( $this, 'ajax_recalc_orders_batch' ) );

        /** Dedicated admin pages under WooCommerce */
        add_action( 'admin_menu', array( $this, 'register_admin_pages' ) );

        /** Enqueue admin scripts and styles */
        add_action( 'admin_enqueue_scripts', array( $this, 'enqueue_admin_assets' ) );
    }

    /** ---------------- Admin assets ---------------- */
    public function enqueue_admin_assets( $hook ) {
        if ( 'woocommerce_page_spvs-inventory' === $hook || 'woocommerce_page_spvs-profit-reports' === $hook ) {
            // Enqueue Chart.js for visualizations
            wp_enqueue_script( 'chart-js', 'https://cdn.jsdelivr.net/npm/chart.js@3.9.1/dist/chart.min.js', array(), '3.9.1', true );

            // Add inline CSS for progress modals
            wp_add_inline_style( 'wp-admin', $this->get_progress_modal_css() );
        }

        if ( 'woocommerce_page_spvs-inventory' === $hook ) {
            // Enqueue import progress modal script
            wp_enqueue_script( 'spvs-cog-import', plugins_url( 'js/cog-import.js', __FILE__ ), array( 'jquery' ), '1.5.3', true );
            wp_localize_script( 'spvs-cog-import', 'spvsCogImport', array(
                'ajaxurl' => admin_url( 'admin-ajax.php' ),
                'nonce' => wp_create_nonce( 'spvs_cog_import' ),
            ) );
        }

        if ( 'woocommerce_page_spvs-profit-reports' === $hook ) {
            // Enqueue order recalculation progress modal script
            wp_enqueue_script( 'spvs-order-recalc', plugins_url( 'js/order-recalc.js', __FILE__ ), array( 'jquery' ), '1.5.3', true );
            wp_localize_script( 'spvs-order-recalc', 'spvsRecalcOrders', array(
                'ajaxurl' => admin_url( 'admin-ajax.php' ),
                'nonce' => wp_create_nonce( 'spvs_recalc_orders' ),
            ) );
        }
    }

    private function get_progress_modal_css() {
        return '
            #spvs-import-modal, #spvs-recalc-modal {
                display: none;
                position: fixed;
                z-index: 100000;
                left: 0;
                top: 0;
                width: 100%;
                height: 100%;
                background-color: rgba(0,0,0,0.7);
            }
            #spvs-import-modal-content, #spvs-recalc-modal-content {
                background-color: #fff;
                margin: 10% auto;
                padding: 30px;
                border-radius: 8px;
                width: 90%;
                max-width: 600px;
                box-shadow: 0 4px 20px rgba(0,0,0,0.3);
            }
            #spvs-import-modal h2, #spvs-recalc-modal h2 {
                margin-top: 0;
                color: #2271b1;
            }
            #spvs-progress-bar-container, #spvs-recalc-progress-bar-container {
                width: 100%;
                background-color: #e0e0e0;
                border-radius: 10px;
                height: 30px;
                margin: 20px 0;
                overflow: hidden;
            }
            #spvs-progress-bar, #spvs-recalc-progress-bar {
                height: 100%;
                background: linear-gradient(90deg, #00a32a 0%, #00ba37 100%);
                width: 0%;
                transition: width 0.3s ease;
                display: flex;
                align-items: center;
                justify-content: center;
                color: white;
                font-weight: bold;
                font-size: 14px;
            }
            #spvs-progress-status, #spvs-recalc-progress-status {
                text-align: center;
                margin: 15px 0;
                font-size: 16px;
                color: #333;
            }
            #spvs-progress-details {
                background: #f0f0f0;
                padding: 15px;
                border-radius: 5px;
                margin: 15px 0;
                font-family: monospace;
                font-size: 13px;
            }
            #spvs-progress-details div {
                margin: 5px 0;
            }
            .spvs-progress-label {
                font-weight: bold;
                display: inline-block;
                width: 120px;
            }
            #spvs-import-complete-btn {
                display: none;
                margin-top: 20px;
                width: 100%;
                padding: 12px;
                font-size: 16px;
            }
        ';
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
        $raw = isset( $_POST[ self::PRODUCT_COST_META ] ) ? wp_unslash( $_POST[ self::PRODUCT_COST_META ] ) : '';
        $value = $raw !== '' ? wc_clean( $raw ) : '';
        $value = $value !== '' ? wc_format_decimal( $value, wc_get_price_decimals() ) : '';
        if ( $value === '' ) { $product->delete_meta_data( self::PRODUCT_COST_META ); }
        else { $product->update_meta_data( self::PRODUCT_COST_META, $value ); }
        $product->save();
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
            $raw = wp_unslash( $_POST[ self::PRODUCT_COST_META ][ $variation_id ] );
            $value = $raw !== '' ? wc_clean( $raw ) : '';
            $value = $value !== '' ? wc_format_decimal( $value, wc_get_price_decimals() ) : '';
            if ( $value === '' ) { delete_post_meta( $variation_id, self::PRODUCT_COST_META ); }
            else { update_post_meta( $variation_id, self::PRODUCT_COST_META, $value ); }
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
        $processed = 0; $managed = 0; $qty_gt0 = 0; $with_cost = 0;

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

                // Get unit cost - if no cost set, skip this product
                $unit_cost = (float) $this->get_product_cost( $pid );
                if ( $unit_cost <= 0 ) {
                    delete_post_meta( $pid, self::PRODUCT_COST_TOTAL_META );
                    delete_post_meta( $pid, self::PRODUCT_RETAIL_TOTAL_META );
                    continue;
                }

                $with_cost++;

                // Get quantity - use stock quantity if managed, otherwise default to 1 for valuation
                $qty = $product->managing_stock() ? (int) $product->get_stock_quantity() : 1;
                if ( $product->managing_stock() ) {
                    $managed++;
                    if ( $qty > 0 ) $qty_gt0++;
                    // If stock managed but qty is 0, skip from totals
                    if ( $qty <= 0 ) {
                        delete_post_meta( $pid, self::PRODUCT_COST_TOTAL_META );
                        delete_post_meta( $pid, self::PRODUCT_RETAIL_TOTAL_META );
                        continue;
                    }
                }

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
            'tcop'      => wc_format_decimal( $tcop_total, wc_get_price_decimals() ),
            'retail'    => wc_format_decimal( $retail_total, wc_get_price_decimals() ),
            'count'     => (int) $processed,
            'managed'   => (int) $managed,
            'qty_gt0'   => (int) $qty_gt0,
            'with_cost' => (int) $with_cost,
            'updated'   => time(),
        ), false );
    }

    /** ---------------- Data Backup & Protection ---------------- */
    public function maybe_schedule_backup_cron() {
        if ( ! wp_next_scheduled( 'spvs_daily_cost_backup' ) ) {
            $timestamp = strtotime( '03:00:00' ); // 3 AM daily
            if ( ! $timestamp || $timestamp <= time() ) $timestamp = time() + HOUR_IN_SECONDS;
            wp_schedule_event( $timestamp, 'daily', 'spvs_daily_cost_backup' );
        }
    }

    public function create_cost_data_backup() {
        global $wpdb;

        // Get all cost data in batches to reduce server load
        $batch_size = 100;
        $offset = 0;
        $all_costs = array();

        while ( true ) {
            $costs_batch = $wpdb->get_results( $wpdb->prepare( "
                SELECT pm.post_id, pm.meta_value as cost
                FROM {$wpdb->postmeta} pm
                INNER JOIN {$wpdb->posts} p ON pm.post_id = p.ID
                WHERE pm.meta_key = %s
                AND p.post_type IN ('product', 'product_variation')
                AND p.post_status = 'publish'
                LIMIT %d OFFSET %d
            ", self::PRODUCT_COST_META, $batch_size, $offset ), ARRAY_A );

            if ( empty( $costs_batch ) ) {
                break; // No more results
            }

            $all_costs = array_merge( $all_costs, $costs_batch );
            $offset += $batch_size;

            // Throttle: small delay between batches to reduce server load
            if ( count( $costs_batch ) === $batch_size ) {
                usleep( 100000 ); // 0.1 second delay between batches
            }
        }

        if ( empty( $all_costs ) ) return false;

        // Create backup with timestamp
        $backup_key = self::BACKUP_OPTION_PREFIX . date( 'Y_m_d_H_i_s' );
        $backup_data = array(
            'timestamp' => time(),
            'count'     => count( $all_costs ),
            'data'      => $all_costs,
            'version'   => '1.4.8'
        );

        // Save backup
        update_option( $backup_key, $backup_data, false );

        // Update latest backup pointer
        update_option( self::BACKUP_LATEST_OPTION, $backup_key, false );

        // Rotate old backups (keep only MAX_BACKUPS)
        $this->rotate_old_backups();

        return $backup_key;
    }

    private function rotate_old_backups() {
        global $wpdb;

        // Get all backup options
        $backups = $wpdb->get_results( $wpdb->prepare(
            "SELECT option_name FROM {$wpdb->options}
            WHERE option_name LIKE %s
            ORDER BY option_name DESC",
            $wpdb->esc_like( self::BACKUP_OPTION_PREFIX ) . '%'
        ), ARRAY_A );

        // Delete old backups beyond MAX_BACKUPS
        if ( count( $backups ) > self::MAX_BACKUPS ) {
            $to_delete = array_slice( $backups, self::MAX_BACKUPS );
            foreach ( $to_delete as $backup ) {
                delete_option( $backup['option_name'] );
            }
        }

        // Update count
        update_option( self::BACKUP_COUNT_OPTION, count( $backups ), false );
    }

    public function get_available_backups() {
        global $wpdb;

        $backups = $wpdb->get_results( $wpdb->prepare(
            "SELECT option_name, option_value FROM {$wpdb->options}
            WHERE option_name LIKE %s
            ORDER BY option_name DESC",
            $wpdb->esc_like( self::BACKUP_OPTION_PREFIX ) . '%'
        ), ARRAY_A );

        $formatted = array();
        foreach ( $backups as $backup ) {
            $data = maybe_unserialize( $backup['option_value'] );
            if ( is_array( $data ) && isset( $data['timestamp'] ) ) {
                $formatted[] = array(
                    'key'       => $backup['option_name'],
                    'timestamp' => $data['timestamp'],
                    'count'     => isset( $data['count'] ) ? $data['count'] : 0,
                    'date'      => date( 'Y-m-d H:i:s', $data['timestamp'] ),
                    'age'       => human_time_diff( $data['timestamp'], time() ) . ' ago'
                );
            }
        }

        return $formatted;
    }

    public function handle_manual_backup() {
        if ( ! current_user_can( 'manage_woocommerce' ) ) wp_die( esc_html__( 'Insufficient permissions.', 'spvs-cost-profit' ) );
        check_admin_referer( 'spvs_backup_costs_now' );

        $backup_key = $this->create_cost_data_backup();

        if ( $backup_key ) {
            $redirect = add_query_arg( array(
                'page'     => 'spvs-inventory',
                'spvs_msg' => 'backup_created'
            ), admin_url( 'admin.php' ) );
        } else {
            $redirect = add_query_arg( array(
                'page'     => 'spvs-inventory',
                'spvs_msg' => 'backup_failed'
            ), admin_url( 'admin.php' ) );
        }

        wp_safe_redirect( $redirect );
        exit;
    }

    public function handle_restore_costs() {
        if ( ! current_user_can( 'manage_woocommerce' ) ) wp_die( esc_html__( 'Insufficient permissions.', 'spvs-cost-profit' ) );
        check_admin_referer( 'spvs_restore_costs' );

        $backup_key = isset( $_POST['backup_key'] ) ? sanitize_text_field( $_POST['backup_key'] ) : '';

        if ( empty( $backup_key ) ) {
            wp_safe_redirect( add_query_arg( array(
                'page'     => 'spvs-inventory',
                'spvs_msg' => 'restore_no_backup'
            ), admin_url( 'admin.php' ) ) );
            exit;
        }

        // Get backup data
        $backup_data = get_option( $backup_key );

        if ( ! $backup_data || ! isset( $backup_data['data'] ) ) {
            wp_safe_redirect( add_query_arg( array(
                'page'     => 'spvs-inventory',
                'spvs_msg' => 'restore_invalid_backup'
            ), admin_url( 'admin.php' ) ) );
            exit;
        }

        // Create a backup before restoring (safety!)
        $this->create_cost_data_backup();

        // Restore costs
        $restored = 0;
        foreach ( $backup_data['data'] as $item ) {
            if ( isset( $item['post_id'] ) && isset( $item['cost'] ) ) {
                update_post_meta( $item['post_id'], self::PRODUCT_COST_META, $item['cost'] );
                $restored++;
            }
        }

        wp_safe_redirect( add_query_arg( array(
            'page'     => 'spvs-inventory',
            'spvs_msg' => 'restore_success:' . $restored
        ), admin_url( 'admin.php' ) ) );
        exit;
    }

    public function export_backup_data() {
        if ( ! current_user_can( 'manage_woocommerce' ) ) wp_die( esc_html__( 'Insufficient permissions.', 'spvs-cost-profit' ) );
        check_admin_referer( 'spvs_export_backup' );

        $backup_key = isset( $_GET['backup_key'] ) ? sanitize_text_field( $_GET['backup_key'] ) : '';

        if ( empty( $backup_key ) ) {
            $backup_key = get_option( self::BACKUP_LATEST_OPTION );
        }

        $backup_data = get_option( $backup_key );

        if ( ! $backup_data || ! isset( $backup_data['data'] ) ) {
            wp_die( esc_html__( 'Backup not found.', 'spvs-cost-profit' ) );
        }

        $filename = 'spvs-backup-' . date( 'Y-m-d-His', $backup_data['timestamp'] ) . '.csv';
        header( 'Content-Type: text/csv; charset=utf-8' );
        header( 'Content-Disposition: attachment; filename=' . $filename );

        $out = fopen( 'php://output', 'w' );
        fputcsv( $out, array( 'product_id', 'cost' ) );

        foreach ( $backup_data['data'] as $item ) {
            fputcsv( $out, array( $item['post_id'], $item['cost'] ) );
        }

        fclose( $out );
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

        if ( empty( $_FILES['spvs_costs_file']['tmp_name'] ) ) { wp_safe_redirect( add_query_arg( array( 'page' => 'spvs-inventory', 'spvs_msg' => 'no_file' ), admin_url( 'admin.php' ) ) ); exit; }
        $tmp = $_FILES['spvs_costs_file']['tmp_name'];
        $fh = fopen( $tmp, 'r' );
        if ( ! $fh ) { wp_safe_redirect( add_query_arg( array( 'page' => 'spvs-inventory', 'spvs_msg' => 'open_fail' ), admin_url( 'admin.php' ) ) ); exit; }

        $header = fgetcsv( $fh ); if ( ! is_array( $header ) ) { $header = array(); }
        $header = array_map( 'sanitize_key', $header );
        if ( ! in_array( 'cost', $header, true ) ) { fclose( $fh ); wp_safe_redirect( add_query_arg( array( 'page' => 'spvs-inventory', 'spvs_msg' => 'missing_cost_col' ), admin_url( 'admin.php' ) ) ); exit; }

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

            $ok = update_post_meta( $product->get_id(), self::PRODUCT_COST_META, $value );
            if ( false === $ok ) { $errors++; } else { $updated++; }

            if ( $updated % 200 == 0 ) { usleep(200000); }
        }
        fclose( $fh );

        if ( ! empty( $misses ) ) { set_transient( self::IMPORT_MISSES_TRANSIENT, $misses, HOUR_IN_SECONDS ); }

        $recalc = isset( $_POST['spvs_recalc_after'] ) && $_POST['spvs_recalc_after'] === '1';
        if ( $recalc ) { $this->recalculate_inventory_totals(); }

        $msg = sprintf( 'import_done:%d:%d:%d:%d', $total, $updated, $skipped, $errors );
        wp_safe_redirect( add_query_arg( array( 'page' => 'spvs-inventory', 'spvs_msg' => rawurlencode( $msg ) ), admin_url( 'admin.php' ) ) ); exit;
    }

    /** ---------------- Cost of Goods Import ---------------- */

    /**
     * Detect if WooCommerce Cost of Goods data exists
     * Checks for _wc_cog_cost meta key (official WooCommerce Cost of Goods plugin)
     *
     * @return array Array with 'found' (bool), 'count' (int), 'sample_products' (array)
     */
    private function detect_cost_of_goods_data() {
        global $wpdb;

        // Check for _wc_cog_cost meta key (official WooCommerce Cost of Goods)
        $count = $wpdb->get_var( "
            SELECT COUNT(DISTINCT pm.post_id)
            FROM {$wpdb->postmeta} pm
            INNER JOIN {$wpdb->posts} p ON pm.post_id = p.ID
            WHERE pm.meta_key = '_wc_cog_cost'
            AND pm.meta_value != ''
            AND p.post_type IN ('product', 'product_variation')
            AND p.post_status = 'publish'
        " );

        $count = (int) $count;

        if ( $count === 0 ) {
            return array(
                'found' => false,
                'count' => 0,
                'sample_products' => array(),
            );
        }

        // Get a few sample products to show
        $samples = $wpdb->get_results( "
            SELECT p.ID, p.post_title, pm.meta_value as cog_cost
            FROM {$wpdb->postmeta} pm
            INNER JOIN {$wpdb->posts} p ON pm.post_id = p.ID
            WHERE pm.meta_key = '_wc_cog_cost'
            AND pm.meta_value != ''
            AND p.post_type IN ('product', 'product_variation')
            AND p.post_status = 'publish'
            ORDER BY p.ID ASC
            LIMIT 5
        ", ARRAY_A );

        return array(
            'found' => true,
            'count' => $count,
            'sample_products' => $samples,
        );
    }

    /**
     * Import cost data from WooCommerce Cost of Goods plugin
     * Copies _wc_cog_cost to _spvs_cost_price
     */
    public function import_from_cost_of_goods() {
        if ( ! current_user_can( 'manage_woocommerce' ) ) {
            wp_die( esc_html__( 'You do not have permission to import cost data.', 'spvs-cost-profit' ) );
        }
        check_admin_referer( 'spvs_import_from_cog' );

        global $wpdb;

        // Create a backup first
        $this->create_cost_data_backup();

        // Get all products with _wc_cog_cost
        $products = $wpdb->get_results( "
            SELECT pm.post_id, pm.meta_value as cog_cost
            FROM {$wpdb->postmeta} pm
            INNER JOIN {$wpdb->posts} p ON pm.post_id = p.ID
            WHERE pm.meta_key = '_wc_cog_cost'
            AND pm.meta_value != ''
            AND pm.meta_value != '0'
            AND p.post_type IN ('product', 'product_variation')
            AND p.post_status = 'publish'
        ", ARRAY_A );

        $imported = 0;
        $skipped = 0;
        $updated = 0;
        $batch_size = 10; // Process 10 products at a time
        $batch_count = 0;

        foreach ( $products as $product_data ) {
            $product_id = (int) $product_data['post_id'];
            $cog_cost = trim( $product_data['cog_cost'] );

            if ( $cog_cost === '' || $cog_cost === '0' ) {
                $skipped++;
                continue;
            }

            // Format the cost value
            $formatted_cost = wc_format_decimal( $cog_cost, wc_get_price_decimals() );
            $existing_cost = get_post_meta( $product_id, self::PRODUCT_COST_META, true );

            // Always overwrite with COG cost (fallback non-AJAX method defaults to overwrite)
            update_post_meta( $product_id, self::PRODUCT_COST_META, $formatted_cost );

            // Track if this was new or updated
            if ( $existing_cost && $existing_cost !== '' ) {
                $updated++;
            } else {
                $imported++;
            }

            // Batch throttling: delay 1 second after every 10 products (max 1 request/sec)
            $batch_count++;
            if ( $batch_count >= $batch_size ) {
                sleep( 1 ); // 1 second delay between batches
                $batch_count = 0;
            }
        }

        // Recalculate inventory totals after import
        $this->recalculate_inventory_totals();

        $msg = sprintf( 'cog_import_done:%d:%d:%d', $imported, $updated, $skipped );
        wp_safe_redirect( add_query_arg( array(
            'page' => 'spvs-inventory',
            'spvs_msg' => rawurlencode( $msg )
        ), admin_url( 'admin.php' ) ) );
        exit;
    }

    /**
     * AJAX handler for batch import with progress tracking
     */
    public function ajax_import_cog_batch() {
        check_ajax_referer( 'spvs_cog_import', 'nonce' );

        if ( ! current_user_can( 'manage_woocommerce' ) ) {
            wp_send_json_error( array( 'message' => 'Insufficient permissions' ) );
        }

        global $wpdb;

        $offset = isset( $_POST['offset'] ) ? (int) $_POST['offset'] : 0;
        $overwrite = isset( $_POST['overwrite'] ) && $_POST['overwrite'] === '1';
        $delete_after = isset( $_POST['delete_after'] ) && $_POST['delete_after'] === '1';
        $batch_size = 10; // Process 10 at a time
        $is_first_batch = ( $offset === 0 );

        // Store options in transient for subsequent batches
        if ( $is_first_batch ) {
            set_transient( 'spvs_cog_import_options', array(
                'overwrite' => $overwrite,
                'delete_after' => $delete_after
            ), HOUR_IN_SECONDS );
        } else {
            $options = get_transient( 'spvs_cog_import_options' );
            if ( $options ) {
                $overwrite = $options['overwrite'];
                $delete_after = $options['delete_after'];
            }
        }

        // Create backup on first batch
        if ( $is_first_batch ) {
            $this->create_cost_data_backup();
        }

        // Get total count (only on first batch)
        if ( $is_first_batch ) {
            $total = $wpdb->get_var( "
                SELECT COUNT(DISTINCT pm.post_id)
                FROM {$wpdb->postmeta} pm
                INNER JOIN {$wpdb->posts} p ON pm.post_id = p.ID
                WHERE pm.meta_key = '_wc_cog_cost'
                AND pm.meta_value != ''
                AND pm.meta_value != '0'
                AND p.post_type IN ('product', 'product_variation')
                AND p.post_status = 'publish'
            " );
            set_transient( 'spvs_cog_import_total', $total, HOUR_IN_SECONDS );
        } else {
            $total = get_transient( 'spvs_cog_import_total' );
        }

        // Get batch of products
        $products = $wpdb->get_results( $wpdb->prepare( "
            SELECT pm.post_id, pm.meta_value as cog_cost
            FROM {$wpdb->postmeta} pm
            INNER JOIN {$wpdb->posts} p ON pm.post_id = p.ID
            WHERE pm.meta_key = '_wc_cog_cost'
            AND pm.meta_value != ''
            AND pm.meta_value != '0'
            AND p.post_type IN ('product', 'product_variation')
            AND p.post_status = 'publish'
            LIMIT %d OFFSET %d
        ", $batch_size, $offset ), ARRAY_A );

        $imported = 0;
        $updated = 0;
        $skipped = 0;

        foreach ( $products as $product_data ) {
            $product_id = (int) $product_data['post_id'];
            $cog_cost = trim( $product_data['cog_cost'] );

            if ( $cog_cost === '' || $cog_cost === '0' ) {
                $skipped++;
                continue;
            }

            // Format the cost value
            $formatted_cost = wc_format_decimal( $cog_cost, wc_get_price_decimals() );
            $existing_cost = get_post_meta( $product_id, self::PRODUCT_COST_META, true );

            // Import logic based on overwrite option
            if ( $overwrite ) {
                // Always overwrite existing costs
                update_post_meta( $product_id, self::PRODUCT_COST_META, $formatted_cost );
                if ( $existing_cost && $existing_cost !== '' ) {
                    $updated++;
                } else {
                    $imported++;
                }
            } else {
                // Only import if no existing cost
                if ( ! $existing_cost || $existing_cost === '' || $existing_cost === '0' ) {
                    update_post_meta( $product_id, self::PRODUCT_COST_META, $formatted_cost );
                    $imported++;
                } else {
                    $skipped++;
                }
            }

            // Delete COG data if requested (per product)
            if ( $delete_after ) {
                delete_post_meta( $product_id, '_wc_cog_cost' );
            }
        }

        $processed = $offset + count( $products );
        $is_complete = ( $processed >= $total || empty( $products ) );

        // Recalculate inventory on last batch
        if ( $is_complete ) {
            $this->recalculate_inventory_totals();
            delete_transient( 'spvs_cog_import_total' );
            delete_transient( 'spvs_cog_import_options' );
        }

        wp_send_json_success( array(
            'processed' => $processed,
            'total' => $total,
            'imported' => $imported,
            'updated' => $updated,
            'skipped' => $skipped,
            'complete' => $is_complete,
            'percentage' => $total > 0 ? round( ( $processed / $total ) * 100 ) : 100
        ) );
    }

    /** ---------------- Order Profit Recalculation (Batch) ---------------- */
    public function ajax_recalc_orders_batch() {
        check_ajax_referer( 'spvs_recalc_orders', 'nonce' );

        if ( ! current_user_can( 'manage_woocommerce' ) ) {
            wp_send_json_error( array( 'message' => 'Insufficient permissions' ) );
        }

        $offset = isset( $_POST['offset'] ) ? (int) $_POST['offset'] : 0;
        $batch_size = 20; // Process 20 orders at a time
        $is_first_batch = ( $offset === 0 );

        // Get total count (cache it for subsequent batches)
        if ( $is_first_batch ) {
            $total = (int) wc_orders_count( apply_filters( 'spvs_profit_report_order_statuses', array( 'wc-completed', 'wc-processing' ) ) );
            set_transient( 'spvs_recalc_total', $total, HOUR_IN_SECONDS );
        } else {
            $total = (int) get_transient( 'spvs_recalc_total' );
            if ( ! $total ) {
                $total = (int) wc_orders_count( apply_filters( 'spvs_profit_report_order_statuses', array( 'wc-completed', 'wc-processing' ) ) );
            }
        }

        if ( $total <= 0 ) {
            wp_send_json_error( array( 'message' => 'No orders found to recalculate' ) );
        }

        // Get batch of orders
        $orders = wc_get_orders( array(
            'status' => apply_filters( 'spvs_profit_report_order_statuses', array( 'completed', 'processing' ) ),
            'limit'  => $batch_size,
            'offset' => $offset,
            'orderby' => 'ID',
            'order'   => 'ASC',
        ) );

        $recalculated = 0;
        foreach ( $orders as $order ) {
            if ( ! $order instanceof WC_Order ) continue;

            // Force recalculation by removing stored profit
            $order->delete_meta_data( self::ORDER_TOTAL_PROFIT_META );
            $order->save_meta_data();

            // Recalculate with current costs
            $this->recalculate_order_total_profit( $order );
            $recalculated++;
        }

        $processed = $offset + $recalculated;
        $is_complete = ( $processed >= $total || empty( $orders ) );

        // Clean up transient on completion
        if ( $is_complete ) {
            delete_transient( 'spvs_recalc_total' );
        }

        wp_send_json_success( array(
            'processed'    => $processed,
            'total'        => $total,
            'recalculated' => $recalculated,
            'complete'     => $is_complete,
            'percentage'   => $total > 0 ? round( ( $processed / $total ) * 100 ) : 100
        ) );
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

    /** --------------- Monthly profit reports --------------- */
    private function get_monthly_profit_data( $start_date = null, $end_date = null ) {
        global $wpdb;

        // Default to last 12 months if no dates provided
        if ( ! $start_date ) {
            $start_date = date( 'Y-m-01', strtotime( '-11 months' ) );
        }
        if ( ! $end_date ) {
            $end_date = date( 'Y-m-t' );
        }

        // Use WooCommerce order query for accurate revenue matching Analytics
        $order_statuses = apply_filters( 'spvs_profit_report_order_statuses', array( 'completed', 'processing' ) );

        // Get orders using WooCommerce query
        $args = array(
            'limit'        => -1,
            'status'       => $order_statuses,
            'date_created' => $start_date . '...' . $end_date,
            'return'       => 'ids',
        );

        $order_ids = wc_get_orders( $args );

        // Group orders by month
        $monthly_data = array();

        foreach ( $order_ids as $order_id ) {
            $order = wc_get_order( $order_id );
            if ( ! $order ) continue;

            $date = $order->get_date_created();
            if ( ! $date ) continue;

            $month = $date->format( 'Y-m' );

            if ( ! isset( $monthly_data[ $month ] ) ) {
                $monthly_data[ $month ] = array(
                    'month'         => $month,
                    'order_count'   => 0,
                    'total_profit'  => 0,
                    'total_revenue' => 0,
                );
            }

            // Get gross sales (this matches WooCommerce Analytics "Gross sales")
            // Gross Sales = Sum of line item subtotals (products BEFORE discounts)
            $revenue = 0;
            foreach ( $order->get_items() as $item ) {
                // get_subtotal() returns line item price BEFORE discounts/coupons
                $revenue += (float) $item->get_subtotal();
            }

            // Get profit from meta
            $profit = get_post_meta( $order_id, self::ORDER_TOTAL_PROFIT_META, true );
            $profit = $profit !== '' ? (float) $profit : 0;

            $monthly_data[ $month ]['order_count']++;
            $monthly_data[ $month ]['total_revenue'] += $revenue;
            $monthly_data[ $month ]['total_profit'] += $profit;
        }

        // Convert to objects for consistency
        $results = array();
        ksort( $monthly_data );

        foreach ( $monthly_data as $data ) {
            $results[] = (object) $data;
        }

        return $results;
    }

    public function export_monthly_profit_csv() {
        if ( ! current_user_can( 'read' ) ) wp_die( esc_html__( 'Insufficient permissions.', 'spvs-cost-profit' ) );
        check_admin_referer( 'spvs_export_monthly_profit' );

        $start_date = isset( $_GET['start_date'] ) ? sanitize_text_field( $_GET['start_date'] ) : date( 'Y-m-01', strtotime( '-11 months' ) );
        $end_date = isset( $_GET['end_date'] ) ? sanitize_text_field( $_GET['end_date'] ) : date( 'Y-m-t' );

        $data = $this->get_monthly_profit_data( $start_date, $end_date );

        $filename = 'monthly-profit-' . date( 'Ymd-His' ) . '.csv';
        header( 'Content-Type: text/csv; charset=utf-8' );
        header( 'Content-Disposition: attachment; filename=' . $filename );

        $out = fopen( 'php://output', 'w' );
        fputcsv( $out, array( 'Month', 'Orders', 'Total Revenue', 'Total Profit', 'Profit Margin %', 'Avg Profit/Order' ) );

        foreach ( $data as $row ) {
            $revenue = (float) $row->total_revenue;
            $profit = (float) $row->total_profit;
            $orders = (int) $row->order_count;
            $margin = $revenue > 0 ? ( $profit / $revenue ) * 100 : 0;
            $avg_profit = $orders > 0 ? $profit / $orders : 0;

            fputcsv( $out, array(
                $row->month,
                $orders,
                number_format( $revenue, 2, '.', '' ),
                number_format( $profit, 2, '.', '' ),
                number_format( $margin, 2, '.', '' ),
                number_format( $avg_profit, 2, '.', '' ),
            ) );
        }

        fclose( $out );
        exit;
    }

    /** --------------- Admin pages --------------- */
    public function register_admin_pages() {
        add_submenu_page(
            'woocommerce',
            __( 'SPVS Inventory Value', 'spvs-cost-profit' ),
            __( 'SPVS Inventory', 'spvs-cost-profit' ),
            'read',
            'spvs-inventory',
            array( $this, 'render_inventory_admin_page' )
        );

        add_submenu_page(
            'woocommerce',
            __( 'SPVS Profit Reports', 'spvs-cost-profit' ),
            __( 'SPVS Profit Reports', 'spvs-cost-profit' ),
            'read',
            'spvs-profit-reports',
            array( $this, 'render_profit_reports_page' )
        );

        add_submenu_page(
            'woocommerce',
            __( 'SPVS Data Recovery', 'spvs-cost-profit' ),
            __( 'SPVS Data Recovery', 'spvs-cost-profit' ),
            'manage_woocommerce',
            'spvs-data-recovery',
            array( $this, 'render_data_recovery_page' )
        );
    }

    public function render_profit_reports_page() {
        if ( ! current_user_can( 'read' ) ) wp_die( esc_html__( 'Insufficient permissions.', 'spvs-cost-profit' ) );

        // Get date range from request or default to last 12 months
        $start_date = isset( $_GET['start_date'] ) ? sanitize_text_field( $_GET['start_date'] ) : date( 'Y-m-01', strtotime( '-11 months' ) );
        $end_date = isset( $_GET['end_date'] ) ? sanitize_text_field( $_GET['end_date'] ) : date( 'Y-m-t' );

        $monthly_data = $this->get_monthly_profit_data( $start_date, $end_date );

        $export_url = add_query_arg( array(
            'action'     => 'spvs_export_monthly_profit',
            '_wpnonce'   => wp_create_nonce( 'spvs_export_monthly_profit' ),
            'start_date' => $start_date,
            'end_date'   => $end_date,
        ), admin_url( 'admin-post.php' ) );

        echo '<div class="wrap">';
        echo '<h1>' . esc_html__( 'Monthly Profit Reports', 'spvs-cost-profit' ) . '</h1>';

        // Show success message if redirected after recalculation
        if ( isset( $_GET['spvs_recalc_done'] ) ) {
            $recalc_count = (int) $_GET['spvs_recalc_done'];
            echo '<div class="notice notice-success is-dismissible"><p>';
            echo sprintf( esc_html__( '✅ Successfully recalculated profit for %d orders using current cost data!', 'spvs-cost-profit' ), $recalc_count );
            echo '</p></div>';
        }

        // Date range selector
        echo '<form method="get" style="margin: 20px 0; padding: 15px; background: #fff; border: 1px solid #ccc; display: inline-block;">';
        echo '<input type="hidden" name="page" value="spvs-profit-reports" />';
        echo '<label><strong>' . esc_html__( 'Start Date:', 'spvs-cost-profit' ) . '</strong> ';
        echo '<input type="date" name="start_date" value="' . esc_attr( $start_date ) . '" /></label> ';
        echo '<label style="margin-left: 15px;"><strong>' . esc_html__( 'End Date:', 'spvs-cost-profit' ) . '</strong> ';
        echo '<input type="date" name="end_date" value="' . esc_attr( $end_date ) . '" /></label> ';
        echo '<button class="button button-primary" style="margin-left: 15px;">' . esc_html__( 'Update', 'spvs-cost-profit' ) . '</button> ';
        echo '<a class="button" href="' . esc_url( $export_url ) . '" style="margin-left: 10px;">' . esc_html__( 'Export CSV', 'spvs-cost-profit' ) . '</a>';
        echo '</form>';

        // Recalculate All Orders button
        echo '<div style="margin: 20px 0; padding: 15px; background: #fff; border: 1px solid #ccc;">';
        echo '<h3 style="margin-top:0;">' . esc_html__( 'Recalculate Historical Profit', 'spvs-cost-profit' ) . '</h3>';
        echo '<p>' . esc_html__( 'If you imported costs after orders were placed, use this to recalculate profit for all historical orders using current cost data.', 'spvs-cost-profit' ) . '</p>';
        echo '<button type="button" id="spvs-recalc-orders-btn" class="button button-secondary">' . esc_html__( '🔄 Recalculate All Orders', 'spvs-cost-profit' ) . '</button>';
        echo '</div>';

        if ( empty( $monthly_data ) ) {
            echo '<div class="notice notice-warning"><p>' . esc_html__( 'No profit data found for the selected date range.', 'spvs-cost-profit' ) . '</p></div>';
        } else {
            // Prepare data for chart
            $months = array();
            $profits = array();
            $revenues = array();
            $total_profit = 0;
            $total_revenue = 0;

            foreach ( $monthly_data as $row ) {
                $months[] = $row->month;
                $profit = (float) $row->total_profit;
                $revenue = (float) $row->total_revenue;
                $profits[] = $profit;
                $revenues[] = $revenue;
                $total_profit += $profit;
                $total_revenue += $revenue;
            }

            // Summary cards
            echo '<div style="display: flex; gap: 20px; margin: 20px 0; flex-wrap: wrap;">';

            echo '<div style="flex: 1; min-width: 200px; background: #fff; padding: 20px; border-left: 4px solid #2271b1; box-shadow: 0 1px 3px rgba(0,0,0,0.1);">';
            echo '<h3 style="margin: 0 0 10px 0; color: #666;">' . esc_html__( 'Total Profit', 'spvs-cost-profit' ) . '</h3>';
            echo '<p style="font-size: 24px; font-weight: bold; margin: 0; color: #2271b1;">' . wp_kses_post( wc_price( $total_profit ) ) . '</p>';
            echo '</div>';

            echo '<div style="flex: 1; min-width: 200px; background: #fff; padding: 20px; border-left: 4px solid #00a32a; box-shadow: 0 1px 3px rgba(0,0,0,0.1);">';
            echo '<h3 style="margin: 0 0 10px 0; color: #666;">' . esc_html__( 'Total Revenue', 'spvs-cost-profit' ) . '</h3>';
            echo '<p style="font-size: 24px; font-weight: bold; margin: 0; color: #00a32a;">' . wp_kses_post( wc_price( $total_revenue ) ) . '</p>';
            echo '</div>';

            $avg_margin = $total_revenue > 0 ? ( $total_profit / $total_revenue ) * 100 : 0;
            echo '<div style="flex: 1; min-width: 200px; background: #fff; padding: 20px; border-left: 4px solid #d63638; box-shadow: 0 1px 3px rgba(0,0,0,0.1);">';
            echo '<h3 style="margin: 0 0 10px 0; color: #666;">' . esc_html__( 'Avg Margin', 'spvs-cost-profit' ) . '</h3>';
            echo '<p style="font-size: 24px; font-weight: bold; margin: 0; color: #d63638;">' . number_format( $avg_margin, 2 ) . '%</p>';
            echo '</div>';

            echo '</div>';

            // Chart
            echo '<div style="background: #fff; padding: 20px; margin: 20px 0; box-shadow: 0 1px 3px rgba(0,0,0,0.1);">';
            echo '<canvas id="spvs-profit-chart" style="max-height: 400px;"></canvas>';
            echo '</div>';

            // Data table
            echo '<table class="widefat striped" style="margin-top: 20px;">';
            echo '<thead><tr>';
            echo '<th>' . esc_html__( 'Month', 'spvs-cost-profit' ) . '</th>';
            echo '<th>' . esc_html__( 'Orders', 'spvs-cost-profit' ) . '</th>';
            echo '<th>' . esc_html__( 'Revenue', 'spvs-cost-profit' ) . '</th>';
            echo '<th>' . esc_html__( 'Profit', 'spvs-cost-profit' ) . '</th>';
            echo '<th>' . esc_html__( 'Margin %', 'spvs-cost-profit' ) . '</th>';
            echo '<th>' . esc_html__( 'Avg Profit/Order', 'spvs-cost-profit' ) . '</th>';
            echo '</tr></thead><tbody>';

            foreach ( $monthly_data as $row ) {
                $revenue = (float) $row->total_revenue;
                $profit = (float) $row->total_profit;
                $orders = (int) $row->order_count;
                $margin = $revenue > 0 ? ( $profit / $revenue ) * 100 : 0;
                $avg_profit = $orders > 0 ? $profit / $orders : 0;

                echo '<tr>';
                echo '<td><strong>' . esc_html( $row->month ) . '</strong></td>';
                echo '<td>' . esc_html( $orders ) . '</td>';
                echo '<td>' . wp_kses_post( wc_price( $revenue ) ) . '</td>';
                echo '<td>' . wp_kses_post( wc_price( $profit ) ) . '</td>';
                echo '<td>' . number_format( $margin, 2 ) . '%</td>';
                echo '<td>' . wp_kses_post( wc_price( $avg_profit ) ) . '</td>';
                echo '</tr>';
            }

            echo '</tbody></table>';

            // Chart.js script
            ?>
            <script>
            document.addEventListener('DOMContentLoaded', function() {
                var ctx = document.getElementById('spvs-profit-chart');
                if (ctx && typeof Chart !== 'undefined') {
                    new Chart(ctx, {
                        type: 'bar',
                        data: {
                            labels: <?php echo wp_json_encode( $months ); ?>,
                            datasets: [{
                                label: '<?php echo esc_js( __( 'Profit', 'spvs-cost-profit' ) ); ?>',
                                data: <?php echo wp_json_encode( $profits ); ?>,
                                backgroundColor: 'rgba(34, 113, 177, 0.7)',
                                borderColor: 'rgba(34, 113, 177, 1)',
                                borderWidth: 1,
                                yAxisID: 'y'
                            }, {
                                label: '<?php echo esc_js( __( 'Revenue', 'spvs-cost-profit' ) ); ?>',
                                data: <?php echo wp_json_encode( $revenues ); ?>,
                                backgroundColor: 'rgba(0, 163, 42, 0.7)',
                                borderColor: 'rgba(0, 163, 42, 1)',
                                borderWidth: 1,
                                yAxisID: 'y'
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
                                    text: '<?php echo esc_js( __( 'Monthly Profit & Revenue', 'spvs-cost-profit' ) ); ?>'
                                }
                            },
                            scales: {
                                y: {
                                    type: 'linear',
                                    display: true,
                                    position: 'left',
                                    ticks: {
                                        callback: function(value) {
                                            return '<?php echo html_entity_decode( get_woocommerce_currency_symbol(), ENT_QUOTES, 'UTF-8' ); ?>' + value.toFixed(2);
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

        // Progress Modal for Recalculation
        echo '<div id="spvs-recalc-modal">';
        echo '<div id="spvs-recalc-modal-content">';
        echo '<h2>🔄 ' . esc_html__( 'Recalculating Order Profit', 'spvs-cost-profit' ) . '</h2>';
        echo '<div id="spvs-recalc-progress-bar-container">';
        echo '<div id="spvs-recalc-progress-bar">0%</div>';
        echo '</div>';
        echo '<p id="spvs-recalc-progress-status">' . esc_html__( 'Initializing...', 'spvs-cost-profit' ) . '</p>';
        echo '<div style="margin-top:15px; font-size:13px; color:#666;">';
        echo '<strong>' . esc_html__( 'Details:', 'spvs-cost-profit' ) . '</strong><br/>';
        echo esc_html__( 'Recalculated:', 'spvs-cost-profit' ) . ' <span id="spvs-recalc-detail-count">0</span><br/>';
        echo esc_html__( 'Processed:', 'spvs-cost-profit' ) . ' <span id="spvs-recalc-detail-processed">0 / 0</span>';
        echo '</div>';
        echo '<button type="button" id="spvs-recalc-complete-btn" class="button button-primary" style="margin-top:20px; display:none;">' . esc_html__( 'Close & Reload Page', 'spvs-cost-profit' ) . '</button>';
        echo '</div>';
        echo '</div>';

        echo '</div>';
    }

    /** --------------- Data Recovery Page --------------- */
    public function render_data_recovery_page() {
        if ( ! current_user_can( 'manage_woocommerce' ) ) wp_die( esc_html__( 'Insufficient permissions.', 'spvs-cost-profit' ) );

        global $wpdb;

        // Handle recovery action
        if ( isset( $_POST['spvs_recover_from_revisions'] ) ) {
            check_admin_referer( 'spvs_recover_from_revisions' );

            $recovered = 0;
            $revision_costs = $wpdb->get_results( "
                SELECT pm.post_id, pm.meta_value as cost, p.post_parent
                FROM {$wpdb->postmeta} pm
                INNER JOIN {$wpdb->posts} p ON pm.post_id = p.ID
                WHERE pm.meta_key = '" . self::PRODUCT_COST_META . "'
                AND p.post_type = 'revision'
                ORDER BY p.post_modified DESC
            " );

            if ( ! empty( $revision_costs ) ) {
                $processed_parents = array();
                foreach ( $revision_costs as $rev ) {
                    if ( $rev->post_parent && ! in_array( $rev->post_parent, $processed_parents ) ) {
                        $current_cost = get_post_meta( $rev->post_parent, self::PRODUCT_COST_META, true );
                        if ( empty( $current_cost ) ) {
                            update_post_meta( $rev->post_parent, self::PRODUCT_COST_META, $rev->cost );
                            $recovered++;
                            $processed_parents[] = $rev->post_parent;
                        }
                    }
                }
            }

            if ( $recovered > 0 ) {
                // Create backup after recovery
                $this->create_cost_data_backup();
                echo '<div class="notice notice-success"><p>' . sprintf( esc_html__( '✅ Successfully recovered %d product costs from revisions! A backup has been created.', 'spvs-cost-profit' ), $recovered ) . '</p></div>';
            } else {
                echo '<div class="notice notice-warning"><p>' . esc_html__( 'No products were recovered. Either data already exists or no revision data was found.', 'spvs-cost-profit' ) . '</p></div>';
            }
        }

        // Get current cost data count
        $current_count = $wpdb->get_var( "
            SELECT COUNT(*) FROM {$wpdb->postmeta}
            WHERE meta_key = '" . self::PRODUCT_COST_META . "'
        " );

        // Check for revision data
        $revision_count = $wpdb->get_var( "
            SELECT COUNT(*) FROM {$wpdb->postmeta} pm
            INNER JOIN {$wpdb->posts} p ON pm.post_id = p.ID
            WHERE pm.meta_key = '" . self::PRODUCT_COST_META . "'
            AND p.post_type = 'revision'
        " );

        echo '<div class="wrap">';
        echo '<h1>🔧 ' . esc_html__( 'Data Recovery & Diagnostics', 'spvs-cost-profit' ) . '</h1>';
        echo '<p>' . esc_html__( 'This page helps you diagnose and recover cost data if it has been lost.', 'spvs-cost-profit' ) . '</p>';

        // Current Data Status
        echo '<div style="background: #fff; padding: 20px; margin: 20px 0; border-left: 4px solid ' . ( $current_count > 0 ? '#00a32a' : '#d63638' ) . '; box-shadow: 0 1px 3px rgba(0,0,0,0.1);">';
        echo '<h2>' . esc_html__( 'Current Data Status', 'spvs-cost-profit' ) . '</h2>';

        if ( $current_count > 0 ) {
            echo '<p style="font-size: 18px;"><strong style="color: #00a32a;">✅ ' . esc_html__( 'Cost data found:', 'spvs-cost-profit' ) . '</strong> ' . esc_html( number_format( $current_count ) ) . ' ' . esc_html__( 'products with cost prices', 'spvs-cost-profit' ) . '</p>';
            echo '<p>' . esc_html__( 'Your cost data appears to be intact.', 'spvs-cost-profit' ) . '</p>';
        } else {
            echo '<p style="font-size: 18px;"><strong style="color: #d63638;">⚠️ ' . esc_html__( 'No cost data found', 'spvs-cost-profit' ) . '</strong></p>';
            echo '<p>' . esc_html__( 'No product cost prices were found in the database. This may indicate data loss.', 'spvs-cost-profit' ) . '</p>';
        }
        echo '</div>';

        // Revision Backup Status
        echo '<div style="background: #fff; padding: 20px; margin: 20px 0; border-left: 4px solid ' . ( $revision_count > 0 ? '#2271b1' : '#dba617' ) . '; box-shadow: 0 1px 3px rgba(0,0,0,0.1);">';
        echo '<h2>' . esc_html__( 'Backup Data in Revisions', 'spvs-cost-profit' ) . '</h2>';

        if ( $revision_count > 0 ) {
            echo '<p style="font-size: 18px;"><strong style="color: #2271b1;">💾 ' . esc_html__( 'Backup data found:', 'spvs-cost-profit' ) . '</strong> ' . esc_html( number_format( $revision_count ) ) . ' ' . esc_html__( 'cost entries in post revisions', 'spvs-cost-profit' ) . '</p>';
            echo '<p>' . esc_html__( 'WordPress has saved cost data in post revision history. This can be used for recovery.', 'spvs-cost-profit' ) . '</p>';

            if ( $current_count == 0 ) {
                echo '<form method="post">';
                wp_nonce_field( 'spvs_recover_from_revisions' );
                echo '<button type="submit" name="spvs_recover_from_revisions" class="button button-primary button-hero" style="margin-top: 15px;">🔄 ' . esc_html__( 'Recover Cost Data from Revisions', 'spvs-cost-profit' ) . '</button>';
                echo '<p class="description">' . esc_html__( 'This will restore cost data from WordPress post revisions for products that are missing cost values. A backup will be created after recovery.', 'spvs-cost-profit' ) . '</p>';
                echo '</form>';
            } else {
                echo '<p><em>' . esc_html__( 'Recovery not needed - current data exists.', 'spvs-cost-profit' ) . '</em></p>';
            }
        } else {
            echo '<p style="font-size: 18px;"><strong style="color: #dba617;">⚠️ ' . esc_html__( 'No backup data found', 'spvs-cost-profit' ) . '</strong></p>';
            echo '<p>' . esc_html__( 'No cost data was found in WordPress post revisions.', 'spvs-cost-profit' ) . '</p>';
        }
        echo '</div>';

        // Export Current Data
        if ( $current_count > 0 ) {
            $export_url = add_query_arg( array(
                'action'   => 'spvs_export_backup',
                '_wpnonce' => wp_create_nonce( 'spvs_export_backup' )
            ), admin_url( 'admin-post.php' ) );

            echo '<div style="background: #fff; padding: 20px; margin: 20px 0; border-left: 4px solid #2271b1; box-shadow: 0 1px 3px rgba(0,0,0,0.1);">';
            echo '<h2>' . esc_html__( 'Export Current Data', 'spvs-cost-profit' ) . '</h2>';
            echo '<p>' . esc_html__( 'Download your current cost data as a CSV backup file.', 'spvs-cost-profit' ) . '</p>';
            echo '<a href="' . esc_url( $export_url ) . '" class="button button-primary">📥 ' . esc_html__( 'Download Cost Data Backup (CSV)', 'spvs-cost-profit' ) . '</a>';
            echo '</div>';
        }

        // Alternative Recovery Options
        echo '<div style="background: #fff; padding: 20px; margin: 20px 0; box-shadow: 0 1px 3px rgba(0,0,0,0.1);">';
        echo '<h2>' . esc_html__( 'Alternative Recovery Options', 'spvs-cost-profit' ) . '</h2>';
        echo '<ul style="line-height: 1.8;">';
        echo '<li><strong>' . esc_html__( 'Automatic Backups:', 'spvs-cost-profit' ) . '</strong> ' . esc_html__( 'Check WooCommerce > SPVS Inventory > Data Backup & Protection for automatic backups (created daily at 3 AM).', 'spvs-cost-profit' ) . '</li>';
        echo '<li><strong>' . esc_html__( 'Hosting Backup:', 'spvs-cost-profit' ) . '</strong> ' . esc_html__( 'Contact your hosting provider to restore your database from a backup before the data loss occurred.', 'spvs-cost-profit' ) . '</li>';
        echo '<li><strong>' . esc_html__( 'Previous CSV Export:', 'spvs-cost-profit' ) . '</strong> ' . esc_html__( 'If you have a previous CSV export, use the import feature at WooCommerce > SPVS Inventory to restore costs.', 'spvs-cost-profit' ) . '</li>';
        echo '<li><strong>' . esc_html__( 'Manual Entry:', 'spvs-cost-profit' ) . '</strong> ' . esc_html__( 'Edit products individually to re-enter cost prices.', 'spvs-cost-profit' ) . '</li>';
        echo '</ul>';
        echo '</div>';

        // Prevention Tips
        echo '<div style="background: #f0f6fc; padding: 20px; margin: 20px 0; border-left: 4px solid #2271b1;">';
        echo '<h2>🛡️ ' . esc_html__( 'Preventing Future Data Loss', 'spvs-cost-profit' ) . '</h2>';
        echo '<ul style="line-height: 1.8;">';
        echo '<li><strong>' . esc_html__( 'Daily Backups:', 'spvs-cost-profit' ) . '</strong> ' . esc_html__( 'The plugin automatically backs up cost data daily at 3:00 AM (keeps 7 days).', 'spvs-cost-profit' ) . '</li>';
        echo '<li><strong>' . esc_html__( 'Manual Backups:', 'spvs-cost-profit' ) . '</strong> ' . esc_html__( 'Create backups anytime at WooCommerce > SPVS Inventory > "Create Backup Now".', 'spvs-cost-profit' ) . '</li>';
        echo '<li><strong>' . esc_html__( 'Export Regularly:', 'spvs-cost-profit' ) . '</strong> ' . esc_html__( 'Download CSV backups weekly and store them securely offline.', 'spvs-cost-profit' ) . '</li>';
        echo '<li><strong>' . esc_html__( 'Before Updates:', 'spvs-cost-profit' ) . '</strong> ' . esc_html__( 'Always create a manual backup before updating plugins or WordPress.', 'spvs-cost-profit' ) . '</li>';
        echo '</ul>';
        echo '</div>';

        echo '</div>';
    }

    public function render_inventory_admin_page() {
        if ( ! current_user_can( 'read' ) ) wp_die( esc_html__( 'Insufficient permissions.', 'spvs-cost-profit' ) );
        $totals = get_option( self::INVENTORY_TOTALS_OPTION, array() );
        $tcop   = isset( $totals['tcop'] ) ? (float) $totals['tcop'] : 0.0;
        $retail = isset( $totals['retail'] ) ? (float) $totals['retail'] : 0.0;
        $updated = isset( $totals['updated'] ) ? (int) $totals['updated'] : 0;
        $count   = isset( $totals['count'] ) ? (int) $totals['count'] : 0;
        $managed = isset( $totals['managed'] ) ? (int) $totals['managed'] : 0;
        $qty_gt0 = isset( $totals['qty_gt0'] ) ? (int) $totals['qty_gt0'] : 0;

        // Column picker
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

        echo '<div class="wrap"><h1>' . esc_html__( 'SPVS Inventory Value', 'spvs-cost-profit' ) . '</h1>';

        // Auto-recovery notice
        $auto_recovered = get_transient( 'spvs_auto_recovery_done' );
        if ( $auto_recovered ) {
            echo '<div class="notice notice-success is-dismissible"><p><strong>🎉 ' . esc_html__( 'Auto-Recovery Successful!', 'spvs-cost-profit' ) . '</strong> ' . sprintf( esc_html__( 'Recovered %d product costs from revisions during plugin upgrade. A backup has been created.', 'spvs-cost-profit' ), (int) $auto_recovered ) . '</p></div>';
            delete_transient( 'spvs_auto_recovery_done' );
        }

        // Notices
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
                    printf( '<div class="notice notice-success is-dismissible"><p><strong>✅ ' . esc_html__( 'Cost of Goods Import Complete!', 'spvs-cost-profit' ) . '</strong><br/>%s</p></div>',
                        esc_html( sprintf( __( 'Imported: %d new costs, Updated: %d existing costs, Skipped: %d (already set or zero)', 'spvs-cost-profit' ), (int)$parts[1], (int)$parts[2], (int)$parts[3] ) )
                    );
                }
            }
        }

        echo '<p><strong>TCOP:</strong> ' . wp_kses_post( wc_price( $tcop ) ) . ' &nbsp; ';
        echo '<strong>Retail:</strong> ' . wp_kses_post( wc_price( $retail ) ) . ' &nbsp; ';
        echo '<strong>Spread:</strong> ' . wp_kses_post( wc_price( $retail - $tcop ) ) . '</p>';
        if ( $updated ) echo '<p style="opacity:.75;">' . esc_html__( 'Updated', 'spvs-cost-profit' ) . ' ' . esc_html( human_time_diff( $updated, time() ) ) . ' ' . esc_html__( 'ago', 'spvs-cost-profit' ) . '</p>';
        echo '<p>' . esc_html__( 'Items processed:', 'spvs-cost-profit' ) . ' ' . esc_html( $count ) . ' · ' . esc_html__( 'Managing stock:', 'spvs-cost-profit' ) . ' ' . esc_html( $managed ) . ' · ' . esc_html__( 'Qty > 0:', 'spvs-cost-profit' ) . ' ' . esc_html( $qty_gt0 ) . '</p>';

        // Warning if TCOP is 0 but there are costs in the database
        if ( $tcop == 0 && $count > 0 ) {
            global $wpdb;
            $cost_count = $wpdb->get_var( $wpdb->prepare(
                "SELECT COUNT(*) FROM {$wpdb->postmeta} WHERE meta_key = %s AND meta_value != '' AND meta_value != '0'",
                self::PRODUCT_COST_META
            ) );
            if ( $cost_count > 0 ) {
                echo '<div class="notice notice-warning inline" style="margin:15px 0; padding:10px;"><p>';
                echo '<strong>⚠️ ' . esc_html__( 'TCOP is $0 but costs are set!', 'spvs-cost-profit' ) . '</strong><br/>';
                echo sprintf( esc_html__( 'Found %d products with costs, but TCOP = $0. This usually means:', 'spvs-cost-profit' ), $cost_count ) . '<br/>';
                echo '• ' . esc_html__( 'Products don\'t have "Manage stock" enabled in WooCommerce', 'spvs-cost-profit' ) . '<br/>';
                echo '• ' . esc_html__( 'Stock quantities are set to 0', 'spvs-cost-profit' ) . '<br/>';
                echo '<strong>' . esc_html__( 'Fix: Enable stock management on your products and set quantities, then click "Recalculate Now"', 'spvs-cost-profit' ) . '</strong>';
                echo '</p></div>';
            }
        }

        echo '<p style="margin-top:6px; opacity:.8;">' . esc_html__( 'Note: If a variation has no cost set, it will use the parent product cost automatically.', 'spvs-cost-profit' ) . '</p>';
        echo '<p style="margin-top:6px; opacity:.8;"><strong>' . esc_html__( 'Important:', 'spvs-cost-profit' ) . '</strong> ' . esc_html__( 'TCOP only counts products with stock management enabled and quantity > 0.', 'spvs-cost-profit' ) . '</p>';

        echo '<form method="get" style="margin:12px 0; display:flex; align-items:flex-end; gap:12px; flex-wrap:wrap;">';
        echo '<input type="hidden" name="page" value="spvs-inventory" />';
        echo '<label><strong>' . esc_html__( 'Columns:', 'spvs-cost-profit' ) . '</strong><br/>';
        echo '<select name="spvs_cols[]" multiple size="6" style="min-width:220px;">';
        foreach ( $available as $key => $label ) { $sel = in_array( $key, $selected, true ) ? ' selected' : ''; echo '<option value="' . esc_attr( $key ) . '"' . $sel . '>' . esc_html( $label ) . '</option>'; }
        echo '</select></label>';
        echo '<button class="button">' . esc_html__( 'Apply', 'spvs-cost-profit' ) . '</button>';
        echo '<a class="button button-primary" href="' . esc_url( $export_url ) . '">' . esc_html__( 'Export CSV (selected columns)', 'spvs-cost-profit' ) . '</a>';
        echo '<a class="button" href="' . esc_url( admin_url( 'admin-post.php?action=spvs_cost_template_csv' ) ) . '">' . esc_html__( 'Download Cost Template', 'spvs-cost-profit' ) . '</a>';
        echo '<a class="button" href="' . esc_url( admin_url( 'admin-post.php?action=spvs_cost_missing_csv' ) ) . '">' . esc_html__( 'Download items with Qty>0 & missing cost', 'spvs-cost-profit' ) . '</a>';
        echo '<a class="button" href="' . esc_url( admin_url( 'admin-post.php?action=spvs_recalc_inventory&_wpnonce=' . wp_create_nonce( 'spvs_recalc_inventory' ) ) ) . '">' . esc_html__( 'Recalculate Now', 'spvs-cost-profit' ) . '</a>';
        echo '</form>';

        // Cost of Goods Import Section
        $cog_data = $this->detect_cost_of_goods_data();
        if ( $cog_data['found'] ) {
            echo '<hr style="margin:18px 0;"><h2>📦 ' . esc_html__( 'Import from WooCommerce Cost of Goods', 'spvs-cost-profit' ) . ' <span style="font-size:14px; color:#00a32a; font-weight:normal;">(NEW in v1.4.8)</span></h2>';

            echo '<div style="background:#e7f7e7; padding:15px; border-radius:5px; border-left:4px solid #00a32a; margin:15px 0;">';
            echo '<p style="margin:0 0 10px 0;"><strong>✅ ' . esc_html__( 'Cost of Goods Data Detected!', 'spvs-cost-profit' ) . '</strong></p>';
            printf( '<p style="margin:0 0 10px 0;">%s</p>',
                sprintf( esc_html__( 'Found %d products with cost data from WooCommerce Cost of Goods plugin.', 'spvs-cost-profit' ), $cog_data['count'] )
            );

            if ( ! empty( $cog_data['sample_products'] ) ) {
                echo '<details style="margin:10px 0;"><summary style="cursor:pointer; font-weight:600;">' . esc_html__( 'Show sample products', 'spvs-cost-profit' ) . '</summary>';
                echo '<table style="margin-top:10px; border-collapse:collapse; width:100%; background:#fff;"><thead><tr style="background:#f0f0f0;">';
                echo '<th style="padding:8px; text-align:left; border:1px solid #ddd;">' . esc_html__( 'Product ID', 'spvs-cost-profit' ) . '</th>';
                echo '<th style="padding:8px; text-align:left; border:1px solid #ddd;">' . esc_html__( 'Product Name', 'spvs-cost-profit' ) . '</th>';
                echo '<th style="padding:8px; text-align:left; border:1px solid #ddd;">' . esc_html__( 'COG Cost', 'spvs-cost-profit' ) . '</th>';
                echo '</tr></thead><tbody>';
                foreach ( $cog_data['sample_products'] as $sample ) {
                    echo '<tr>';
                    echo '<td style="padding:8px; border:1px solid #ddd;">' . esc_html( $sample['ID'] ) . '</td>';
                    echo '<td style="padding:8px; border:1px solid #ddd;">' . esc_html( $sample['post_title'] ) . '</td>';
                    echo '<td style="padding:8px; border:1px solid #ddd;">' . wp_kses_post( wc_price( $sample['cog_cost'] ) ) . '</td>';
                    echo '</tr>';
                }
                echo '</tbody></table></details>';
            }

            echo '<p style="margin:10px 0 0 0;"><strong>' . esc_html__( 'How it works:', 'spvs-cost-profit' ) . '</strong></p>';
            echo '<ul style="margin:5px 0 10px 20px;">';
            echo '<li>' . esc_html__( 'Creates automatic backup before import', 'spvs-cost-profit' ) . '</li>';
            echo '<li>' . esc_html__( 'Imports costs from WooCommerce Cost of Goods (_wc_cog_cost)', 'spvs-cost-profit' ) . '</li>';
            echo '<li>' . esc_html__( 'Skips only zero or empty COG values', 'spvs-cost-profit' ) . '</li>';
            echo '<li>' . esc_html__( 'Recalculates inventory totals after import', 'spvs-cost-profit' ) . '</li>';
            echo '</ul>';

            // Import Options
            echo '<div style="background:#fff; border:1px solid #ddd; padding:15px; margin:15px 0; border-radius:5px;">';
            echo '<h4 style="margin-top:0;">' . esc_html__( 'Import Options', 'spvs-cost-profit' ) . '</h4>';

            echo '<label style="display:block; margin:10px 0;">';
            echo '<input type="checkbox" id="spvs-cog-overwrite" checked /> ';
            echo '<strong>' . esc_html__( 'Overwrite existing costs', 'spvs-cost-profit' ) . '</strong>';
            echo '<br/><span style="color:#666; font-size:13px; margin-left:20px;">' . esc_html__( 'Replace all existing cost data with COG values. If unchecked, only imports products without existing costs.', 'spvs-cost-profit' ) . '</span>';
            echo '</label>';

            echo '<label style="display:block; margin:10px 0;">';
            echo '<input type="checkbox" id="spvs-cog-delete-after" /> ';
            echo '<strong>' . esc_html__( 'Delete Cost of Goods data after import', 'spvs-cost-profit' ) . '</strong>';
            echo '<br/><span style="color:#666; font-size:13px; margin-left:20px;">' . esc_html__( 'Remove _wc_cog_cost meta data after successful import to avoid data duplication.', 'spvs-cost-profit' ) . '</span>';
            echo '</label>';
            echo '</div>';

            echo '<div style="margin-top:10px;">';
            echo '<button type="button" id="spvs-start-cog-import" class="button button-primary" style="background:#00a32a; border-color:#00a32a;">📥 ' . esc_html__( 'Import from Cost of Goods', 'spvs-cost-profit' ) . '</button>';
            echo ' <span style="color:#666; font-size:12px;">' . sprintf( esc_html__( '(%d products will be processed)', 'spvs-cost-profit' ), $cog_data['count'] ) . '</span>';
            echo '</div>';

            // Progress Modal
            echo '<div id="spvs-import-modal">';
            echo '<div id="spvs-import-modal-content">';
            echo '<h2>📦 ' . esc_html__( 'Importing Cost of Goods Data', 'spvs-cost-profit' ) . '</h2>';
            echo '<div id="spvs-progress-bar-container">';
            echo '<div id="spvs-progress-bar">0%</div>';
            echo '</div>';
            echo '<div id="spvs-progress-status">' . esc_html__( 'Initializing...', 'spvs-cost-profit' ) . '</div>';
            echo '<div id="spvs-progress-details">';
            echo '<div><span class="spvs-progress-label">' . esc_html__( 'Imported:', 'spvs-cost-profit' ) . '</span><span id="spvs-detail-imported">0</span></div>';
            echo '<div><span class="spvs-progress-label">' . esc_html__( 'Updated:', 'spvs-cost-profit' ) . '</span><span id="spvs-detail-updated">0</span></div>';
            echo '<div><span class="spvs-progress-label">' . esc_html__( 'Skipped:', 'spvs-cost-profit' ) . '</span><span id="spvs-detail-skipped">0</span></div>';
            echo '<div><span class="spvs-progress-label">' . esc_html__( 'Processed:', 'spvs-cost-profit' ) . '</span><span id="spvs-detail-processed">0 / 0</span></div>';
            echo '</div>';
            echo '<button id="spvs-import-complete-btn" class="button button-primary button-large">' . esc_html__( 'Close & Reload Page', 'spvs-cost-profit' ) . '</button>';
            echo '</div>';
            echo '</div>';

            echo '</div>';
        }

        // Data Backup & Restore Section
        $backups = $this->get_available_backups();
        $latest_backup = ! empty( $backups ) ? $backups[0] : null;

        echo '<hr style="margin:18px 0;"><h2>🔒 ' . esc_html__( 'Data Backup & Protection', 'spvs-cost-profit' ) . ' <span style="font-size:14px; color:#d63638; font-weight:normal;">(NEW in v1.4.1)</span></h2>';

        // Handle backup/restore messages
        if ( isset( $_GET['spvs_msg'] ) ) {
            $m = sanitize_text_field( wp_unslash( $_GET['spvs_msg'] ) );
            if ( 'backup_created' === $m ) {
                echo '<div class="notice notice-success"><p>' . esc_html__( '✅ Backup created successfully!', 'spvs-cost-profit' ) . '</p></div>';
            } elseif ( 'backup_failed' === $m ) {
                echo '<div class="notice notice-error"><p>' . esc_html__( '❌ Backup failed. No cost data found.', 'spvs-cost-profit' ) . '</p></div>';
            } elseif ( 0 === strpos( $m, 'restore_success:' ) ) {
                $restored = str_replace( 'restore_success:', '', $m );
                echo '<div class="notice notice-success"><p>' . sprintf( esc_html__( '✅ Successfully restored %d product costs!', 'spvs-cost-profit' ), (int) $restored ) . '</p></div>';
            } elseif ( 'restore_invalid_backup' === $m ) {
                echo '<div class="notice notice-error"><p>' . esc_html__( '❌ Invalid backup selected.', 'spvs-cost-profit' ) . '</p></div>';
            }
        }

        echo '<div style="background:#f8f9fa; padding:15px; border-radius:5px; border-left:4px solid #2271b1; margin:15px 0;">';
        echo '<p style="margin:0 0 10px 0;"><strong>' . esc_html__( 'Automatic Protection:', 'spvs-cost-profit' ) . '</strong> ' . esc_html__( 'Your cost data is automatically backed up daily at 3:00 AM. Up to 2 backups are kept.', 'spvs-cost-profit' ) . '</p>';

        if ( $latest_backup ) {
            echo '<p style="margin:0;"><strong>' . esc_html__( 'Latest Backup:', 'spvs-cost-profit' ) . '</strong> ' . esc_html( $latest_backup['date'] ) . ' (' . esc_html( $latest_backup['age'] ) . ') - ' . esc_html( $latest_backup['count'] ) . ' ' . esc_html__( 'products', 'spvs-cost-profit' ) . '</p>';
        } else {
            echo '<p style="margin:0; color:#d63638;"><strong>' . esc_html__( '⚠️ No backups found.', 'spvs-cost-profit' ) . '</strong> ' . esc_html__( 'Click "Create Backup Now" to create your first backup.', 'spvs-cost-profit' ) . '</p>';
        }
        echo '</div>';

        // Manual backup button
        echo '<div style="margin:15px 0;">';
        echo '<a href="' . esc_url( admin_url( 'admin-post.php?action=spvs_backup_costs_now&_wpnonce=' . wp_create_nonce( 'spvs_backup_costs_now' ) ) ) . '" class="button button-primary">💾 ' . esc_html__( 'Create Backup Now', 'spvs-cost-profit' ) . '</a>';
        echo '</div>';

        // Available backups list
        if ( ! empty( $backups ) ) {
            echo '<h3>' . esc_html__( 'Available Backups', 'spvs-cost-profit' ) . '</h3>';
            echo '<table class="widefat striped"><thead><tr>';
            echo '<th>' . esc_html__( 'Date & Time', 'spvs-cost-profit' ) . '</th>';
            echo '<th>' . esc_html__( 'Age', 'spvs-cost-profit' ) . '</th>';
            echo '<th>' . esc_html__( 'Products', 'spvs-cost-profit' ) . '</th>';
            echo '<th>' . esc_html__( 'Actions', 'spvs-cost-profit' ) . '</th>';
            echo '</tr></thead><tbody>';

            foreach ( $backups as $backup ) {
                echo '<tr>';
                echo '<td><strong>' . esc_html( $backup['date'] ) . '</strong></td>';
                echo '<td>' . esc_html( $backup['age'] ) . '</td>';
                echo '<td>' . esc_html( $backup['count'] ) . '</td>';
                echo '<td>';

                // Restore form
                echo '<form method="post" action="' . esc_url( admin_url( 'admin-post.php' ) ) . '" style="display:inline; margin-right:10px;" onsubmit="return confirm(\'' . esc_js( __( 'Are you sure you want to restore from this backup? Current data will be backed up first.', 'spvs-cost-profit' ) ) . '\');">';
                echo '<input type="hidden" name="action" value="spvs_restore_costs" />';
                echo '<input type="hidden" name="backup_key" value="' . esc_attr( $backup['key'] ) . '" />';
                wp_nonce_field( 'spvs_restore_costs' );
                echo '<button type="submit" class="button">🔄 ' . esc_html__( 'Restore', 'spvs-cost-profit' ) . '</button>';
                echo '</form>';

                // Export backup
                $export_backup_url = add_query_arg( array(
                    'action'     => 'spvs_export_backup',
                    '_wpnonce'   => wp_create_nonce( 'spvs_export_backup' ),
                    'backup_key' => $backup['key']
                ), admin_url( 'admin-post.php' ) );
                echo '<a href="' . esc_url( $export_backup_url ) . '" class="button">📥 ' . esc_html__( 'Download', 'spvs-cost-profit' ) . '</a>';

                echo '</td>';
                echo '</tr>';
            }

            echo '</tbody></table>';
        }

        // Upload form
        echo '<hr style="margin:18px 0;"><h2>' . esc_html__( 'Import Costs (CSV)', 'spvs-cost-profit' ) . '</h2>';
        echo '<form method="post" action="' . esc_url( admin_url( 'admin-post.php' ) ) . '" enctype="multipart/form-data" style="display:flex; flex-wrap:wrap; gap:12px; align-items:flex-end;">';
        echo '<input type="hidden" name="action" value="spvs_import_costs_csv" />';
        wp_nonce_field( 'spvs_import_costs_csv' );
        echo '<label><strong>' . esc_html__( 'CSV file', 'spvs-cost-profit' ) . '</strong><br><input type="file" name="spvs_costs_file" accept=".csv,text/csv" required /></label>';
        echo '<label><input type="checkbox" name="spvs_recalc_after" value="1" /> ' . esc_html__( 'Recalculate totals after import', 'spvs-cost-profit' ) . '</label>';
        echo '<button class="button button-primary">' . esc_html__( 'Import Costs', 'spvs-cost-profit' ) . '</button>';
        echo '<p class="description" style="width:100%;">' . esc_html__( 'Accepted columns: SKU, Product ID (or variation_id), Slug (parent only), Cost. Header row required: any of "sku" or "product_id"/"variation_id", and "cost".', 'spvs-cost-profit' ) . '</p>';
        echo '</form>';

        // Preview top 100 rows
        $q = new WP_Query( array( 'post_type' => array( 'product', 'product_variation' ), 'post_status' => 'publish', 'posts_per_page' => 100, 'fields' => 'ids', 'no_found_rows' => true ) );
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
        echo '</tbody></table></div>';
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

    // Auto-recovery and backup on activation/upgrade (v1.4.1+)
    if ( class_exists( 'SPVS_Cost_Profit' ) ) {
        $instance = SPVS_Cost_Profit::instance();

        // Check if cost data exists
        global $wpdb;
        $cost_count = $wpdb->get_var( "
            SELECT COUNT(*) FROM {$wpdb->postmeta}
            WHERE meta_key = '_spvs_cost_price'
        " );

        // If no cost data, attempt recovery from revisions
        if ( $cost_count == 0 ) {
            $recovered = 0;
            $revision_costs = $wpdb->get_results( "
                SELECT pm.post_id, pm.meta_value as cost, p.post_parent
                FROM {$wpdb->postmeta} pm
                INNER JOIN {$wpdb->posts} p ON pm.post_id = p.ID
                WHERE pm.meta_key = '_spvs_cost_price'
                AND p.post_type = 'revision'
                ORDER BY p.post_modified DESC
            " );

            if ( ! empty( $revision_costs ) ) {
                $processed_parents = array();
                foreach ( $revision_costs as $rev ) {
                    if ( $rev->post_parent && ! in_array( $rev->post_parent, $processed_parents ) ) {
                        update_post_meta( $rev->post_parent, '_spvs_cost_price', $rev->cost );
                        $recovered++;
                        $processed_parents[] = $rev->post_parent;
                    }
                }

                // Set a flag to show recovery message
                if ( $recovered > 0 ) {
                    set_transient( 'spvs_auto_recovery_done', $recovered, HOUR_IN_SECONDS );
                }
            }
        }

        // Create initial backup
        if ( method_exists( $instance, 'create_cost_data_backup' ) ) {
            $instance->create_cost_data_backup();
        }
    }
} );

// Deactivation: clear cron/transient (leave data intact until uninstall)
register_deactivation_hook( __FILE__, function() {
    $ts = wp_next_scheduled( 'spvs_daily_inventory_recalc' );
    if ( $ts ) { wp_unschedule_event( $ts, 'spvs_daily_inventory_recalc' ); }

    $ts2 = wp_next_scheduled( 'spvs_daily_cost_backup' );
    if ( $ts2 ) { wp_unschedule_event( $ts2, 'spvs_daily_cost_backup' ); }

    delete_transient( SPVS_Cost_Profit::RECALC_LOCK_TRANSIENT );
} );

// Bootstrap
SPVS_Cost_Profit::instance();

endif;
