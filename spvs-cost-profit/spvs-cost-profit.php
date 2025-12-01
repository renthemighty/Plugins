<?php
/**
 * Plugin Name: SPVS Cost & Profit for WooCommerce
 * Description: Simple, reliable cost tracking and profit reporting for WooCommerce
 * Version: 1.7.1
 * Author: Megatron
 * License: GPL-2.0+
 */

if ( ! defined( 'ABSPATH' ) ) { exit; }

final class SPVS_Cost_Profit_V2 {

    private static $instance = null;

    const PRODUCT_COST_META = '_spvs_cost_price';
    const ORDER_PROFIT_META = '_spvs_total_profit';

    public static function instance() {
        if ( is_null( self::$instance ) ) {
            self::$instance = new self();
        }
        return self::$instance;
    }

    private function __construct() {
        // Product cost field
        add_action( 'woocommerce_product_options_pricing', array( $this, 'add_cost_field' ) );
        add_action( 'woocommerce_process_product_meta', array( $this, 'save_cost_field' ) );
        add_action( 'woocommerce_variation_options_pricing', array( $this, 'add_variation_cost_field' ), 10, 3 );
        add_action( 'woocommerce_save_product_variation', array( $this, 'save_variation_cost_field' ), 10, 2 );

        // Auto-calculate profit on order save
        add_action( 'woocommerce_checkout_order_created', array( $this, 'calculate_order_profit' ) );
        add_action( 'woocommerce_update_order', array( $this, 'calculate_order_profit' ) );
        add_action( 'woocommerce_order_refunded', array( $this, 'recalculate_on_refund' ), 10, 2 );

        // Admin pages
        add_action( 'admin_menu', array( $this, 'add_menu_pages' ) );
        add_action( 'admin_enqueue_scripts', array( $this, 'enqueue_scripts' ) );

        // Recalculation handler
        add_action( 'admin_post_spvs_recalculate_all', array( $this, 'handle_recalculate_all' ) );
    }

    /** ============= PRODUCT COST FIELDS ============= */

    public function add_cost_field() {
        woocommerce_wp_text_input( array(
            'id'          => self::PRODUCT_COST_META,
            'label'       => 'Cost Price (' . get_woocommerce_currency_symbol() . ')',
            'desc_tip'    => true,
            'description' => 'Cost of goods for this product',
            'data_type'   => 'price',
        ) );
    }

    public function save_cost_field( $post_id ) {
        $cost = isset( $_POST[ self::PRODUCT_COST_META ] ) ? wc_clean( $_POST[ self::PRODUCT_COST_META ] ) : '';
        update_post_meta( $post_id, self::PRODUCT_COST_META, wc_format_decimal( $cost ) );
    }

    public function add_variation_cost_field( $loop, $variation_data, $variation ) {
        woocommerce_wp_text_input( array(
            'id'          => self::PRODUCT_COST_META . '[' . $loop . ']',
            'label'       => 'Cost Price (' . get_woocommerce_currency_symbol() . ')',
            'value'       => get_post_meta( $variation->ID, self::PRODUCT_COST_META, true ),
            'wrapper_class' => 'form-row form-row-full',
            'data_type'   => 'price',
        ) );
    }

    public function save_variation_cost_field( $variation_id, $i ) {
        $cost = isset( $_POST[ self::PRODUCT_COST_META ][ $i ] ) ? wc_clean( $_POST[ self::PRODUCT_COST_META ][ $i ] ) : '';
        update_post_meta( $variation_id, self::PRODUCT_COST_META, wc_format_decimal( $cost ) );
    }

    /** ============= PROFIT CALCULATION ============= */

    private function get_product_cost( $product_id ) {
        $cost = get_post_meta( $product_id, self::PRODUCT_COST_META, true );

        // If variation has no cost, try parent
        if ( empty( $cost ) ) {
            $product = wc_get_product( $product_id );
            if ( $product && $product->is_type( 'variation' ) ) {
                $parent_id = $product->get_parent_id();
                if ( $parent_id ) {
                    $cost = get_post_meta( $parent_id, self::PRODUCT_COST_META, true );
                }
            }
        }

        return (float) $cost;
    }

    public function calculate_order_profit( $order ) {
        if ( is_numeric( $order ) ) {
            $order = wc_get_order( $order );
        }

        if ( ! $order ) {
            return;
        }

        $total_profit = 0;

        foreach ( $order->get_items( 'line_item' ) as $item ) {
            $product = $item->get_product();
            if ( ! $product ) {
                continue;
            }

            $product_id = $product->get_id();
            $quantity = $item->get_quantity();
            $line_total = (float) $item->get_total(); // Revenue after discounts

            // Get cost
            $unit_cost = $this->get_product_cost( $product_id );
            $total_cost = $unit_cost * $quantity;

            // Calculate line profit
            $line_profit = $line_total - $total_cost;
            $total_profit += $line_profit;
        }

        // Save to order meta
        update_post_meta( $order->get_id(), self::ORDER_PROFIT_META, wc_format_decimal( $total_profit, 2 ) );

        return $total_profit;
    }

    public function recalculate_on_refund( $order_id, $refund_id ) {
        $order = wc_get_order( $order_id );
        if ( $order ) {
            $this->calculate_order_profit( $order );
        }
    }

    /** ============= ADMIN PAGES ============= */

    public function add_menu_pages() {
        add_submenu_page(
            'woocommerce',
            'Profit Reports',
            'Profit Reports',
            'manage_woocommerce',
            'spvs-profit-reports',
            array( $this, 'render_reports_page' )
        );
    }

    public function enqueue_scripts( $hook ) {
        if ( $hook === 'woocommerce_page_spvs-profit-reports' ) {
            wp_enqueue_script( 'chart-js', 'https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.min.js', array(), '4.4.0', false );
        }
    }

    /** ============= REPORTS PAGE ============= */

    public function render_reports_page() {
        // Get date range - default to current month
        $start_date = isset( $_GET['start_date'] ) ? sanitize_text_field( $_GET['start_date'] ) : date( 'Y-m-01' );
        $end_date = isset( $_GET['end_date'] ) ? sanitize_text_field( $_GET['end_date'] ) : date( 'Y-m-t' );

        // Get report data
        $data = $this->get_report_data( $start_date, $end_date );

        ?>
        <div class="wrap">
            <style>
                .wrap { max-width: none !important; }
                .spvs-full-width { width: 100%; max-width: none; }
            </style>
            <h1>📊 Profit Reports</h1>

            <?php if ( isset( $_GET['recalc_success'] ) ) : ?>
                <div class="notice notice-success is-dismissible">
                    <p><strong>✅ Recalculation Complete!</strong> Processed <?php echo esc_html( $_GET['total'] ); ?> orders.</p>
                </div>
            <?php endif; ?>

            <!-- Quick Date Shortcuts -->
            <div class="card" style="padding: 20px; margin: 20px 0;">
                <h2>📅 Quick Select</h2>
                <div style="display: flex; gap: 10px; flex-wrap: wrap;">
                    <a href="<?php echo esc_url( add_query_arg( array( 'page' => 'spvs-profit-reports', 'start_date' => date( 'Y-m-01' ), 'end_date' => date( 'Y-m-t' ) ), admin_url( 'admin.php' ) ) ); ?>" class="button">This Month</a>
                    <a href="<?php echo esc_url( add_query_arg( array( 'page' => 'spvs-profit-reports', 'start_date' => date( 'Y-m-01', strtotime( '-1 month' ) ), 'end_date' => date( 'Y-m-t', strtotime( '-1 month' ) ) ), admin_url( 'admin.php' ) ) ); ?>" class="button">Last Month</a>
                    <a href="<?php echo esc_url( add_query_arg( array( 'page' => 'spvs-profit-reports', 'start_date' => date( 'Y-m-01', strtotime( '-2 months' ) ), 'end_date' => date( 'Y-m-t' ) ), admin_url( 'admin.php' ) ) ); ?>" class="button">Last 3 Months</a>
                    <a href="<?php echo esc_url( add_query_arg( array( 'page' => 'spvs-profit-reports', 'start_date' => date( 'Y-m-01', strtotime( '-5 months' ) ), 'end_date' => date( 'Y-m-t' ) ), admin_url( 'admin.php' ) ) ); ?>" class="button">Last 6 Months</a>
                    <a href="<?php echo esc_url( add_query_arg( array( 'page' => 'spvs-profit-reports', 'start_date' => date( 'Y-01-01' ), 'end_date' => date( 'Y-12-31' ) ), admin_url( 'admin.php' ) ) ); ?>" class="button">This Year</a>
                    <a href="<?php echo esc_url( add_query_arg( array( 'page' => 'spvs-profit-reports', 'start_date' => date( 'Y-01-01', strtotime( '-1 year' ) ), 'end_date' => date( 'Y-12-31', strtotime( '-1 year' ) ) ), admin_url( 'admin.php' ) ) ); ?>" class="button">Last Year</a>
                </div>
            </div>

            <!-- Custom Date Range Selector -->
            <div class="card" style="padding: 20px; margin: 20px 0;">
                <h2>📆 Custom Date Range</h2>
                <form method="get" style="display: flex; gap: 15px; align-items: end; flex-wrap: wrap;">
                    <input type="hidden" name="page" value="spvs-profit-reports">
                    <div>
                        <label><strong>Start Date:</strong></label><br>
                        <input type="date" name="start_date" value="<?php echo esc_attr( $start_date ); ?>" required>
                    </div>
                    <div>
                        <label><strong>End Date:</strong></label><br>
                        <input type="date" name="end_date" value="<?php echo esc_attr( $end_date ); ?>" required>
                    </div>
                    <button type="submit" class="button button-primary">Update Report</button>
                </form>
            </div>

            <!-- Recalculation Tool -->
            <div class="card" style="max-width: 800px; padding: 20px; margin: 20px 0; background: #f0f6fc;">
                <h2>🔄 Recalculate All Orders</h2>
                <p>Click below to recalculate profit for ALL orders using current product costs. This will update historical data.</p>
                <form method="post" action="<?php echo esc_url( admin_url( 'admin-post.php' ) ); ?>" onsubmit="return confirm('This will recalculate ALL orders. Continue?');">
                    <input type="hidden" name="action" value="spvs_recalculate_all">
                    <?php wp_nonce_field( 'spvs_recalculate_all' ); ?>
                    <button type="submit" class="button button-secondary" style="background: #2271b1; color: white; border-color: #2271b1;">
                        🔄 Recalculate All Orders Now
                    </button>
                </form>
            </div>

            <?php if ( empty( $data ) ) : ?>
                <div class="notice notice-warning">
                    <p>No orders found for this date range.</p>
                </div>
            <?php else : ?>

                <!-- Summary Cards -->
                <style>
                    .spvs-summary-grid {
                        display: grid;
                        grid-template-columns: repeat(4, 1fr);
                        gap: 20px;
                        margin: 20px 0;
                    }
                    @media (max-width: 1200px) {
                        .spvs-summary-grid {
                            grid-template-columns: repeat(2, 1fr);
                        }
                    }
                    @media (max-width: 600px) {
                        .spvs-summary-grid {
                            grid-template-columns: 1fr;
                        }
                    }
                </style>
                <div class="spvs-summary-grid">
                    <div class="card" style="padding: 20px; text-align: center;">
                        <h3 style="margin: 0; color: #666; font-size: 14px;">Total Revenue</h3>
                        <p style="font-size: 28px; font-weight: bold; margin: 10px 0; color: #2271b1;">
                            <?php echo wc_price( $data['summary']['revenue'] ); ?>
                        </p>
                    </div>
                    <div class="card" style="padding: 20px; text-align: center;">
                        <h3 style="margin: 0; color: #666; font-size: 14px;">Total Cost</h3>
                        <p style="font-size: 28px; font-weight: bold; margin: 10px 0; color: #d63638;">
                            <?php echo wc_price( $data['summary']['cost'] ); ?>
                        </p>
                    </div>
                    <div class="card" style="padding: 20px; text-align: center;">
                        <h3 style="margin: 0; color: #666; font-size: 14px;">Total Profit</h3>
                        <p style="font-size: 28px; font-weight: bold; margin: 10px 0; color: #00a32a;">
                            <?php echo wc_price( $data['summary']['profit'] ); ?>
                        </p>
                    </div>
                    <div class="card" style="padding: 20px; text-align: center;">
                        <h3 style="margin: 0; color: #666; font-size: 14px;">Profit Margin</h3>
                        <p style="font-size: 28px; font-weight: bold; margin: 10px 0; color: #8c8c8c;">
                            <?php echo number_format( $data['summary']['margin'], 1 ); ?>%
                        </p>
                    </div>
                </div>

                <!-- Chart -->
                <div class="card spvs-full-width" style="padding: 20px; margin: 20px 0;">
                    <canvas id="profit-chart" style="max-height: 400px;"></canvas>
                </div>

                <script>
                document.addEventListener('DOMContentLoaded', function() {
                    if (typeof Chart === 'undefined') {
                        console.error('Chart.js not loaded');
                        return;
                    }

                    new Chart(document.getElementById('profit-chart'), {
                        type: 'bar',
                        data: {
                            labels: <?php echo json_encode( array_column( $data['daily'], 'date' ) ); ?>,
                            datasets: [{
                                label: 'Revenue',
                                data: <?php echo json_encode( array_column( $data['daily'], 'revenue' ) ); ?>,
                                backgroundColor: 'rgba(34, 113, 177, 0.8)'
                            }, {
                                label: 'Profit',
                                data: <?php echo json_encode( array_column( $data['daily'], 'profit' ) ); ?>,
                                backgroundColor: 'rgba(0, 163, 42, 0.8)'
                            }]
                        },
                        options: {
                            responsive: true,
                            plugins: {
                                title: {
                                    display: true,
                                    text: 'Daily Profit & Revenue'
                                }
                            },
                            scales: {
                                y: {
                                    beginAtZero: true,
                                    ticks: {
                                        callback: function(value) {
                                            return '$' + value.toFixed(0);
                                        }
                                    }
                                }
                            }
                        }
                    });
                });
                </script>

                <!-- Data Table -->
                <div class="card spvs-full-width" style="padding: 20px; margin: 20px 0;">
                    <h2>Daily Breakdown</h2>
                    <table class="wp-list-table widefat fixed striped" style="width: 100%;">
                        <thead>
                            <tr>
                                <th>Date</th>
                                <th>Orders</th>
                                <th>Revenue</th>
                                <th>Profit</th>
                                <th>Margin %</th>
                            </tr>
                        </thead>
                        <tbody>
                            <?php foreach ( $data['daily'] as $row ) : ?>
                                <tr>
                                    <td><strong><?php echo esc_html( $row['date'] ); ?></strong></td>
                                    <td><?php echo esc_html( $row['orders'] ); ?></td>
                                    <td><?php echo wc_price( $row['revenue'] ); ?></td>
                                    <td><?php echo wc_price( $row['profit'] ); ?></td>
                                    <td><?php echo number_format( $row['margin'], 2 ); ?>%</td>
                                </tr>
                            <?php endforeach; ?>
                        </tbody>
                    </table>
                </div>

            <?php endif; ?>
        </div>
        <?php
    }

    /** ============= DATA RETRIEVAL ============= */

    private function get_report_data( $start_date, $end_date ) {
        global $wpdb;

        // Get all completed/processing orders in date range
        $order_ids = $wpdb->get_col( $wpdb->prepare( "
            SELECT ID FROM {$wpdb->posts}
            WHERE post_type = 'shop_order'
            AND post_status IN ('wc-completed', 'wc-processing')
            AND post_date >= %s
            AND post_date <= %s
            ORDER BY post_date ASC
        ", $start_date . ' 00:00:00', $end_date . ' 23:59:59' ) );

        if ( empty( $order_ids ) ) {
            return array();
        }

        $daily_data = array();
        $total_revenue = 0;
        $total_cost = 0;
        $total_profit = 0;

        foreach ( $order_ids as $order_id ) {
            $order = wc_get_order( $order_id );
            if ( ! $order ) {
                continue;
            }

            $date = $order->get_date_created()->format( 'Y-m-d' );

            // Calculate revenue and cost
            $revenue = 0;
            $cost = 0;
            foreach ( $order->get_items() as $item ) {
                $revenue += (float) $item->get_total();

                // Calculate cost for this line item
                $product = $item->get_product();
                if ( $product ) {
                    $unit_cost = $this->get_product_cost( $product->get_id() );
                    $cost += $unit_cost * $item->get_quantity();
                }
            }

            // Get profit from meta
            $profit = (float) get_post_meta( $order_id, self::ORDER_PROFIT_META, true );

            // Initialize day if not exists
            if ( ! isset( $daily_data[ $date ] ) ) {
                $daily_data[ $date ] = array(
                    'date' => $date,
                    'orders' => 0,
                    'revenue' => 0,
                    'cost' => 0,
                    'profit' => 0,
                    'margin' => 0,
                );
            }

            $daily_data[ $date ]['orders']++;
            $daily_data[ $date ]['revenue'] += $revenue;
            $daily_data[ $date ]['cost'] += $cost;
            $daily_data[ $date ]['profit'] += $profit;

            $total_revenue += $revenue;
            $total_cost += $cost;
            $total_profit += $profit;
        }

        // Calculate margins
        foreach ( $daily_data as &$day ) {
            $day['margin'] = $day['revenue'] > 0 ? ( $day['profit'] / $day['revenue'] ) * 100 : 0;
        }

        return array(
            'daily' => array_values( $daily_data ),
            'summary' => array(
                'revenue' => $total_revenue,
                'cost' => $total_cost,
                'profit' => $total_profit,
                'margin' => $total_revenue > 0 ? ( $total_profit / $total_revenue ) * 100 : 0,
            ),
        );
    }

    /** ============= RECALCULATION ============= */

    public function handle_recalculate_all() {
        check_admin_referer( 'spvs_recalculate_all' );

        if ( ! current_user_can( 'manage_woocommerce' ) ) {
            wp_die( 'Insufficient permissions' );
        }

        global $wpdb;

        // Get ALL orders
        $order_ids = $wpdb->get_col( "
            SELECT ID FROM {$wpdb->posts}
            WHERE post_type = 'shop_order'
            AND post_status IN ('wc-completed', 'wc-processing')
            ORDER BY ID ASC
        " );

        $total = count( $order_ids );

        // Recalculate each order
        foreach ( $order_ids as $order_id ) {
            delete_post_meta( $order_id, self::ORDER_PROFIT_META );
            $this->calculate_order_profit( $order_id );
        }

        // Redirect back with success message
        wp_redirect( add_query_arg( array(
            'page' => 'spvs-profit-reports',
            'recalc_success' => 1,
            'total' => $total,
        ), admin_url( 'admin.php' ) ) );
        exit;
    }
}

// Initialize
SPVS_Cost_Profit_V2::instance();
