<?php
/**
 * Plugin Name: WooCommerce Top Spenders Export
 * Plugin URI: https://github.com/renthemighty/Plugins
 * Description: Export the top 500 customers by total revenue as a CSV file
 * Version: 1.0.0
 * Author: SPVS
 * Author URI: https://github.com/renthemighty
 * Requires at least: 5.0
 * Tested up to: 6.4
 * Requires PHP: 7.2
 * WC requires at least: 5.0
 * WC tested up to: 8.5
 * License: GPL v2 or later
 * License URI: https://www.gnu.org/licenses/gpl-2.0.html
 * Text Domain: wc-top-spenders
 */

defined('ABSPATH') || exit;

class WC_Top_Spenders_Export {

    private static $instance = null;

    public static function instance() {
        if (null === self::$instance) {
            self::$instance = new self();
        }
        return self::$instance;
    }

    private function __construct() {
        // Admin menu
        add_action('admin_menu', [$this, 'admin_menu']);

        // Handle export action
        add_action('admin_init', [$this, 'handle_export']);
    }

    public function admin_menu() {
        add_menu_page(
            'Top Spenders Export',
            'Top Spenders',
            'manage_woocommerce',
            'wc-top-spenders',
            [$this, 'settings_page'],
            'dashicons-businessman',
            56
        );
    }

    public function settings_page() {
        if (!current_user_can('manage_woocommerce')) {
            return;
        }

        ?>
        <div class="wrap">
            <h1>Top Spenders Export</h1>
            <p>Export the top 500 customers by total revenue to a CSV file.</p>

            <div style="background: white; padding: 20px; border: 1px solid #ccc; max-width: 600px; margin-top: 20px;">
                <h2>Export Settings</h2>
                <p>The CSV file will include the following columns:</p>
                <ul style="list-style: disc; margin-left: 20px;">
                    <li>Customer Name</li>
                    <li>Email Address</li>
                    <li>Phone Number</li>
                    <li>Total Spend</li>
                </ul>

                <form method="post">
                    <?php wp_nonce_field('wc_top_spenders_export', 'wc_top_spenders_nonce'); ?>
                    <input type="hidden" name="action" value="export_top_spenders">
                    <p>
                        <button type="submit" class="button button-primary button-large">
                            Export Top 500 Spenders
                        </button>
                    </p>
                </form>
            </div>

            <?php
            // Show statistics
            $stats = $this->get_statistics();
            ?>
            <div style="background: #f0f0f1; padding: 20px; border: 1px solid #ccc; max-width: 600px; margin-top: 20px;">
                <h3>Statistics</h3>
                <p><strong>Total Customers with Orders:</strong> <?php echo number_format($stats['total_customers']); ?></p>
                <p><strong>Total Completed Orders:</strong> <?php echo number_format($stats['total_orders']); ?></p>
                <p><strong>Total Revenue (Completed Orders):</strong> <?php echo wc_price($stats['total_revenue']); ?></p>
            </div>
        </div>
        <?php
    }

    public function handle_export() {
        // Check if export action is triggered
        if (!isset($_POST['action']) || $_POST['action'] !== 'export_top_spenders') {
            return;
        }

        // Verify nonce
        if (!isset($_POST['wc_top_spenders_nonce']) || !wp_verify_nonce($_POST['wc_top_spenders_nonce'], 'wc_top_spenders_export')) {
            wp_die('Security check failed');
        }

        // Check permissions
        if (!current_user_can('manage_woocommerce')) {
            wp_die('You do not have permission to export data');
        }

        // Get top spenders data
        $top_spenders = $this->get_top_spenders(500);

        // Generate CSV
        $this->generate_csv($top_spenders);
    }

    private function get_top_spenders($limit = 500) {
        global $wpdb;

        // Query to get customer email, total spent
        // We'll get orders with status 'completed' or 'processing'
        $query = "
            SELECT
                pm_email.meta_value as email,
                pm_first.meta_value as first_name,
                pm_last.meta_value as last_name,
                pm_phone.meta_value as phone,
                SUM(p.post_total) as total_spent
            FROM (
                SELECT
                    p.ID as order_id,
                    CAST(pm.meta_value AS DECIMAL(10,2)) as post_total
                FROM {$wpdb->posts} p
                INNER JOIN {$wpdb->postmeta} pm ON p.ID = pm.post_id AND pm.meta_key = '_order_total'
                WHERE p.post_type = 'shop_order'
                AND p.post_status IN ('wc-completed', 'wc-processing')
            ) p
            INNER JOIN {$wpdb->postmeta} pm_email ON p.order_id = pm_email.post_id AND pm_email.meta_key = '_billing_email'
            LEFT JOIN {$wpdb->postmeta} pm_first ON p.order_id = pm_first.post_id AND pm_first.meta_key = '_billing_first_name'
            LEFT JOIN {$wpdb->postmeta} pm_last ON p.order_id = pm_last.post_id AND pm_last.meta_key = '_billing_last_name'
            LEFT JOIN {$wpdb->postmeta} pm_phone ON p.order_id = pm_phone.post_id AND pm_phone.meta_key = '_billing_phone'
            WHERE pm_email.meta_value IS NOT NULL
            AND pm_email.meta_value != ''
            GROUP BY pm_email.meta_value
            ORDER BY total_spent DESC
            LIMIT %d
        ";

        $results = $wpdb->get_results($wpdb->prepare($query, $limit));

        // Process results to format names properly
        $processed_results = [];
        foreach ($results as $customer) {
            $first_name = !empty($customer->first_name) ? $customer->first_name : '';
            $last_name = !empty($customer->last_name) ? $customer->last_name : '';
            $full_name = trim($first_name . ' ' . $last_name);

            // If no name, use email username
            if (empty($full_name)) {
                $full_name = strstr($customer->email, '@', true);
            }

            $processed_results[] = [
                'name' => $full_name,
                'email' => $customer->email,
                'phone' => !empty($customer->phone) ? $customer->phone : 'N/A',
                'total_spent' => floatval($customer->total_spent)
            ];
        }

        return $processed_results;
    }

    private function generate_csv($data) {
        // Set headers for CSV download
        header('Content-Type: text/csv; charset=utf-8');
        header('Content-Disposition: attachment; filename=top-500-spenders-' . date('Y-m-d') . '.csv');
        header('Pragma: no-cache');
        header('Expires: 0');

        // Open output stream
        $output = fopen('php://output', 'w');

        // Add UTF-8 BOM for Excel compatibility
        fprintf($output, chr(0xEF).chr(0xBB).chr(0xBF));

        // Add CSV headers
        fputcsv($output, ['Name', 'Email', 'Phone Number', 'Total Spend']);

        // Add data rows
        foreach ($data as $row) {
            fputcsv($output, [
                $row['name'],
                $row['email'],
                $row['phone'],
                number_format($row['total_spent'], 2, '.', '')
            ]);
        }

        fclose($output);
        exit;
    }

    private function get_statistics() {
        global $wpdb;

        // Get total customers with orders
        $total_customers = $wpdb->get_var("
            SELECT COUNT(DISTINCT pm_email.meta_value)
            FROM {$wpdb->posts} p
            INNER JOIN {$wpdb->postmeta} pm_email ON p.ID = pm_email.post_id AND pm_email.meta_key = '_billing_email'
            WHERE p.post_type = 'shop_order'
            AND p.post_status IN ('wc-completed', 'wc-processing')
            AND pm_email.meta_value IS NOT NULL
            AND pm_email.meta_value != ''
        ");

        // Get total completed orders
        $total_orders = $wpdb->get_var("
            SELECT COUNT(*)
            FROM {$wpdb->posts}
            WHERE post_type = 'shop_order'
            AND post_status IN ('wc-completed', 'wc-processing')
        ");

        // Get total revenue
        $total_revenue = $wpdb->get_var("
            SELECT SUM(CAST(pm.meta_value AS DECIMAL(10,2)))
            FROM {$wpdb->posts} p
            INNER JOIN {$wpdb->postmeta} pm ON p.ID = pm.post_id AND pm.meta_key = '_order_total'
            WHERE p.post_type = 'shop_order'
            AND p.post_status IN ('wc-completed', 'wc-processing')
        ");

        return [
            'total_customers' => intval($total_customers),
            'total_orders' => intval($total_orders),
            'total_revenue' => floatval($total_revenue)
        ];
    }
}

// Initialize plugin only if WooCommerce is active
add_action('plugins_loaded', function() {
    if (class_exists('WooCommerce')) {
        WC_Top_Spenders_Export::instance();
    } else {
        // Show admin notice if WooCommerce is not active
        add_action('admin_notices', function() {
            ?>
            <div class="notice notice-error">
                <p><strong>WooCommerce Top Spenders Export</strong> requires WooCommerce to be installed and active.</p>
            </div>
            <?php
        });
    }
});
