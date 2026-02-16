<?php
/**
 * Plugin Name: WooCommerce Top Spenders Export
 * Plugin URI: https://github.com/renthemighty/Plugins
 * Description: Export all customers with purchase history by total revenue as a CSV file with rate limiting and batch processing
 * Version: 1.4.0
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
    private const BATCH_SIZE = 100; // Process 100 customers per batch
    private const RATE_LIMIT_MS = 1000; // 1 second between batches
    private const TRANSIENT_EXPIRY = 3600; // 1 hour

    public static function instance() {
        if (null === self::$instance) {
            self::$instance = new self();
        }
        return self::$instance;
    }

    private function __construct() {
        // Admin menu
        add_action('admin_menu', [$this, 'admin_menu']);

        // Enqueue scripts
        add_action('admin_enqueue_scripts', [$this, 'enqueue_scripts']);

        // AJAX handlers
        add_action('wp_ajax_wc_top_spenders_start_export', [$this, 'ajax_start_export']);
        add_action('wp_ajax_wc_top_spenders_process_batch', [$this, 'ajax_process_batch']);
        add_action('wp_ajax_wc_top_spenders_download_csv', [$this, 'ajax_download_csv']);
        add_action('wp_ajax_wc_top_spenders_cancel_export', [$this, 'ajax_cancel_export']);
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

    public function enqueue_scripts($hook) {
        if ('toplevel_page_wc-top-spenders' !== $hook) {
            return;
        }

        wp_enqueue_style(
            'wc-top-spenders-admin',
            plugins_url('', __FILE__) . '/assets/admin.css',
            [],
            '1.4.0'
        );

        wp_enqueue_script(
            'wc-top-spenders-admin',
            plugins_url('', __FILE__) . '/assets/admin.js',
            ['jquery'],
            '1.4.0',
            true
        );

        wp_localize_script('wc-top-spenders-admin', 'wcTopSpenders', [
            'ajaxUrl' => admin_url('admin-ajax.php'),
            'nonce' => wp_create_nonce('wc_top_spenders_export'),
            'batchSize' => self::BATCH_SIZE,
            'rateLimitMs' => self::RATE_LIMIT_MS,
            'strings' => [
                'starting' => __('Starting export...', 'wc-top-spenders'),
                'processing' => __('Processing batch %d of %d...', 'wc-top-spenders'),
                'complete' => __('Export complete! Preparing download...', 'wc-top-spenders'),
                'error' => __('An error occurred: %s', 'wc-top-spenders'),
                'cancelled' => __('Export cancelled.', 'wc-top-spenders'),
            ]
        ]);
    }

    public function settings_page() {
        if (!current_user_can('manage_woocommerce')) {
            wp_die(__('You do not have permission to access this page.', 'wc-top-spenders'));
        }

        ?>
        <div class="wrap wc-top-spenders-wrap">
            <h1><?php _e('Top Spenders Export', 'wc-top-spenders'); ?></h1>
            <p><?php _e('Export all registered users sorted by total spend. Users with no orders are included with a spend of $0.00.', 'wc-top-spenders'); ?></p>

            <div class="wc-top-spenders-card">
                <h2><?php _e('Export Settings', 'wc-top-spenders'); ?></h2>
                <p><?php _e('The CSV file will include the following columns:', 'wc-top-spenders'); ?></p>
                <ul class="wc-top-spenders-list">
                    <li><?php _e('Customer Name', 'wc-top-spenders'); ?></li>
                    <li><?php _e('Email Address', 'wc-top-spenders'); ?></li>
                    <li><?php _e('Phone Number', 'wc-top-spenders'); ?></li>
                    <li><?php _e('Total Spend', 'wc-top-spenders'); ?></li>
                </ul>

                <p class="wc-top-spenders-info">
                    <strong><?php _e('Note:', 'wc-top-spenders'); ?></strong>
                    <?php _e('The export processes all customers in batches of 100 with a 1 request per second rate limit to avoid server overload.', 'wc-top-spenders'); ?>
                </p>

                <div id="wc-top-spenders-export-container">
                    <button type="button" id="wc-top-spenders-start-export" class="button button-primary button-large">
                        <?php _e('Export All Spenders', 'wc-top-spenders'); ?>
                    </button>

                    <div id="wc-top-spenders-progress" style="display: none;">
                        <div class="wc-top-spenders-progress-bar">
                            <div class="wc-top-spenders-progress-fill" id="wc-top-spenders-progress-fill"></div>
                        </div>
                        <p id="wc-top-spenders-progress-text"><?php _e('Initializing...', 'wc-top-spenders'); ?></p>
                        <button type="button" id="wc-top-spenders-cancel" class="button">
                            <?php _e('Cancel Export', 'wc-top-spenders'); ?>
                        </button>
                    </div>

                    <div id="wc-top-spenders-complete" style="display: none;">
                        <p class="wc-top-spenders-success">
                            <?php _e('Export completed successfully!', 'wc-top-spenders'); ?>
                        </p>
                        <button type="button" id="wc-top-spenders-download" class="button button-primary button-large">
                            <?php _e('Download CSV File', 'wc-top-spenders'); ?>
                        </button>
                        <button type="button" id="wc-top-spenders-new-export" class="button">
                            <?php _e('Start New Export', 'wc-top-spenders'); ?>
                        </button>
                    </div>

                    <div id="wc-top-spenders-error" style="display: none;">
                        <p class="wc-top-spenders-error"></p>
                        <button type="button" id="wc-top-spenders-retry" class="button button-primary">
                            <?php _e('Try Again', 'wc-top-spenders'); ?>
                        </button>
                    </div>
                </div>
            </div>

            <?php
            // Show statistics
            $stats = $this->get_statistics();
            if (!is_wp_error($stats)):
            ?>
            <div class="wc-top-spenders-card wc-top-spenders-stats">
                <h3><?php _e('Statistics', 'wc-top-spenders'); ?></h3>
                <p><strong><?php _e('Total Registered Users:', 'wc-top-spenders'); ?></strong> <?php echo number_format($stats['total_customers']); ?></p>
                <p><strong><?php _e('Total Completed Orders:', 'wc-top-spenders'); ?></strong> <?php echo number_format($stats['total_orders']); ?></p>
                <p><strong><?php _e('Total Revenue (Completed Orders):', 'wc-top-spenders'); ?></strong> <?php echo wc_price($stats['total_revenue']); ?></p>
            </div>
            <?php else: ?>
            <div class="notice notice-error">
                <p><?php echo esc_html($stats->get_error_message()); ?></p>
            </div>
            <?php endif; ?>
        </div>

        <style>
        .wc-top-spenders-wrap {
            max-width: 800px;
        }
        .wc-top-spenders-card {
            background: white;
            padding: 20px;
            border: 1px solid #ccd0d4;
            box-shadow: 0 1px 1px rgba(0,0,0,.04);
            margin-top: 20px;
        }
        .wc-top-spenders-stats {
            background: #f0f0f1;
        }
        .wc-top-spenders-list {
            list-style: disc;
            margin-left: 20px;
        }
        .wc-top-spenders-info {
            background: #e7f5fe;
            border-left: 4px solid #00a0d2;
            padding: 10px;
            margin: 15px 0;
        }
        .wc-top-spenders-progress-bar {
            width: 100%;
            height: 30px;
            background: #f0f0f1;
            border: 1px solid #ccd0d4;
            border-radius: 3px;
            overflow: hidden;
            margin: 15px 0;
        }
        .wc-top-spenders-progress-fill {
            height: 100%;
            background: linear-gradient(90deg, #00a0d2, #0073aa);
            transition: width 0.3s ease;
            width: 0%;
        }
        #wc-top-spenders-progress-text {
            margin: 10px 0;
            font-weight: 600;
        }
        .wc-top-spenders-success {
            color: #46b450;
            font-weight: 600;
            font-size: 16px;
        }
        .wc-top-spenders-error {
            color: #dc3232;
            font-weight: 600;
        }
        #wc-top-spenders-export-container > * {
            margin-top: 15px;
        }
        </style>
        <?php
    }

    public function ajax_start_export() {
        check_ajax_referer('wc_top_spenders_export', 'nonce');

        if (!current_user_can('manage_woocommerce')) {
            wp_send_json_error(['message' => __('Permission denied.', 'wc-top-spenders')]);
        }

        // Allow extra time for the one-time sort query on large stores, and
        // keep running even if the browser disconnects mid-request.
        @set_time_limit(300);
        ignore_user_abort(true);

        try {
            // Clear any previous export data
            $this->clear_export_data();

            // Run the expensive ORDER BY query exactly once and cache the result.
            // Each batch request will then do a cheap WHERE ID IN (...) lookup.
            $sorted = $this->build_sorted_user_list();

            if (is_wp_error($sorted)) {
                throw new Exception($sorted->get_error_message());
            }

            if (empty($sorted)) {
                throw new Exception(__('No registered users found.', 'wc-top-spenders'));
            }

            $total_to_process = count($sorted);
            $total_batches    = (int) ceil($total_to_process / self::BATCH_SIZE);

            // Persist the sorted list so batches can slice into it cheaply.
            set_transient('wc_top_spenders_sorted_ids', $sorted, self::TRANSIENT_EXPIRY);

            set_transient('wc_top_spenders_export_session', [
                'total_customers' => $total_to_process,
                'total_batches'   => $total_batches,
                'current_batch'   => 0,
                'started'         => time(),
            ], self::TRANSIENT_EXPIRY);

            wp_send_json_success([
                'total_batches'   => $total_batches,
                'total_customers' => $total_to_process,
            ]);
        } catch (Exception $e) {
            wp_send_json_error(['message' => $e->getMessage()]);
        }
    }

    public function ajax_process_batch() {
        check_ajax_referer('wc_top_spenders_export', 'nonce');

        if (!current_user_can('manage_woocommerce')) {
            wp_send_json_error(['message' => __('Permission denied.', 'wc-top-spenders')]);
        }

        @set_time_limit(60);
        ignore_user_abort(true);

        try {
            $batch_number = isset($_POST['batch']) ? intval($_POST['batch']) : 0;

            $session = get_transient('wc_top_spenders_export_session');
            if (!$session) {
                throw new Exception(__('Export session expired. Please start a new export.', 'wc-top-spenders'));
            }

            if ($batch_number < 0 || $batch_number >= $session['total_batches']) {
                throw new Exception(__('Invalid batch number.', 'wc-top-spenders'));
            }

            // Retrieve the pre-computed sorted list (built once during start_export).
            $sorted = get_transient('wc_top_spenders_sorted_ids');
            if (!is_array($sorted)) {
                throw new Exception(__('Sorted user list missing. Please start a new export.', 'wc-top-spenders'));
            }

            // Slice just the IDs for this batch — no ORDER BY, no subquery.
            $offset     = $batch_number * self::BATCH_SIZE;
            $batch_meta = array_slice($sorted, $offset, self::BATCH_SIZE);

            $customers = $this->fetch_user_details($batch_meta);

            if (is_wp_error($customers)) {
                throw new Exception($customers->get_error_message());
            }

            $existing_data = get_transient('wc_top_spenders_export_data');
            if (!is_array($existing_data)) {
                $existing_data = [];
            }

            $existing_data = array_merge($existing_data, $customers);
            set_transient('wc_top_spenders_export_data', $existing_data, self::TRANSIENT_EXPIRY);

            $session['current_batch'] = $batch_number + 1;
            set_transient('wc_top_spenders_export_session', $session, self::TRANSIENT_EXPIRY);

            wp_send_json_success([
                'batch'     => $batch_number,
                'processed' => count($existing_data),
                'total'     => $session['total_customers'],
            ]);
        } catch (Exception $e) {
            wp_send_json_error(['message' => $e->getMessage()]);
        }
    }

    public function ajax_download_csv() {
        check_ajax_referer('wc_top_spenders_export', 'nonce');

        if (!current_user_can('manage_woocommerce')) {
            wp_die(__('Permission denied.', 'wc-top-spenders'));
        }

        try {
            $data = get_transient('wc_top_spenders_export_data');

            if (!is_array($data) || empty($data)) {
                wp_die(__('No export data found. Please start a new export.', 'wc-top-spenders'));
            }

            // Generate and download CSV
            $this->generate_csv($data);

            // Clean up transients after download
            $this->clear_export_data();

        } catch (Exception $e) {
            wp_die($e->getMessage());
        }
    }

    public function ajax_cancel_export() {
        check_ajax_referer('wc_top_spenders_export', 'nonce');

        if (!current_user_can('manage_woocommerce')) {
            wp_send_json_error(['message' => __('Permission denied.', 'wc-top-spenders')]);
        }

        $this->clear_export_data();
        wp_send_json_success();
    }

    private function clear_export_data() {
        delete_transient('wc_top_spenders_export_session');
        delete_transient('wc_top_spenders_export_data');
        delete_transient('wc_top_spenders_sorted_ids');
    }

    /**
     * Run once on export start: returns a sorted array of
     * [ ['id' => int, 'total_spent' => float], ... ] for ALL registered users,
     * ordered by total_spent DESC. Expensive query, but only ever runs once.
     */
    private function build_sorted_user_list() {
        global $wpdb;

        try {
            $results = $wpdb->get_results("
                SELECT
                    u.ID,
                    COALESCE(ot.total_spent, 0) AS total_spent
                FROM {$wpdb->users} u
                LEFT JOIN (
                    SELECT
                        CAST(pm_cust.meta_value AS UNSIGNED) AS user_id,
                        SUM(CAST(pm_total.meta_value AS DECIMAL(10,2))) AS total_spent
                    FROM {$wpdb->posts} p
                    INNER JOIN {$wpdb->postmeta} pm_cust
                        ON p.ID = pm_cust.post_id
                        AND pm_cust.meta_key = '_customer_user'
                        AND pm_cust.meta_value != '0'
                    INNER JOIN {$wpdb->postmeta} pm_total
                        ON p.ID = pm_total.post_id
                        AND pm_total.meta_key = '_order_total'
                    WHERE p.post_type = 'shop_order'
                    AND p.post_status IN ('wc-completed', 'wc-processing')
                    GROUP BY pm_cust.meta_value
                ) AS ot ON u.ID = ot.user_id
                ORDER BY total_spent DESC, u.ID ASC
            ", ARRAY_A);

            if ($wpdb->last_error) {
                return new WP_Error('db_error', $wpdb->last_error);
            }

            // Cast types once so downstream code is clean.
            return array_map(function($row) {
                return [
                    'id'          => (int) $row['ID'],
                    'total_spent' => (float) $row['total_spent'],
                ];
            }, $results);
        } catch (Exception $e) {
            return new WP_Error('db_exception', $e->getMessage());
        }
    }

    /**
     * Called per-batch: fetch name/email/phone for a pre-sliced set of
     * [ ['id' => int, 'total_spent' => float], ... ] rows.
     * No ORDER BY, no subquery — just a simple WHERE ID IN (...) join.
     */
    private function fetch_user_details(array $batch_meta) {
        global $wpdb;

        if (empty($batch_meta)) {
            return [];
        }

        try {
            // Build a lookup map: user_id => total_spent
            $totals_map = [];
            $ids        = [];
            foreach ($batch_meta as $row) {
                $ids[]                    = (int) $row['id'];
                $totals_map[$row['id']]   = $row['total_spent'];
            }

            $id_placeholders = implode(',', array_fill(0, count($ids), '%d'));

            $query = $wpdb->prepare("
                SELECT
                    u.ID,
                    u.user_email                AS email,
                    um_first.meta_value         AS first_name,
                    um_last.meta_value          AS last_name,
                    um_phone.meta_value         AS phone
                FROM {$wpdb->users} u
                LEFT JOIN {$wpdb->usermeta} um_first
                    ON u.ID = um_first.user_id
                    AND um_first.meta_key = 'billing_first_name'
                LEFT JOIN {$wpdb->usermeta} um_last
                    ON u.ID = um_last.user_id
                    AND um_last.meta_key = 'billing_last_name'
                LEFT JOIN {$wpdb->usermeta} um_phone
                    ON u.ID = um_phone.user_id
                    AND um_phone.meta_key = 'billing_phone'
                WHERE u.ID IN ($id_placeholders)
            ", ...$ids);

            $results = $wpdb->get_results($query);

            if ($wpdb->last_error) {
                return new WP_Error('db_error', $wpdb->last_error);
            }

            // Index results by ID so we can merge totals and preserve sort order.
            $by_id = [];
            foreach ($results as $row) {
                $by_id[(int) $row->ID] = $row;
            }

            $processed = [];
            foreach ($ids as $user_id) {
                $row = isset($by_id[$user_id]) ? $by_id[$user_id] : null;

                $first_name = ($row && !empty($row->first_name)) ? sanitize_text_field($row->first_name) : '';
                $last_name  = ($row && !empty($row->last_name))  ? sanitize_text_field($row->last_name)  : '';
                $full_name  = trim($first_name . ' ' . $last_name);
                $email      = $row ? sanitize_email($row->email) : '';

                if (empty($full_name) && !empty($email)) {
                    $parts     = explode('@', $email);
                    $full_name = sanitize_text_field($parts[0]);
                }

                $processed[] = [
                    'name'        => $full_name,
                    'email'       => $email,
                    'phone'       => ($row && !empty($row->phone)) ? sanitize_text_field($row->phone) : 'N/A',
                    'total_spent' => $totals_map[$user_id] ?? 0.0,
                ];
            }

            return $processed;
        } catch (Exception $e) {
            return new WP_Error('db_exception', $e->getMessage());
        }
    }

    private function generate_csv($data) {
        if (!is_array($data) || empty($data)) {
            wp_die(__('No data to export.', 'wc-top-spenders'));
        }

        // Set headers for CSV download
        header('Content-Type: text/csv; charset=utf-8');
        header('Content-Disposition: attachment; filename=top-spenders-' . date('Y-m-d-His') . '.csv');
        header('Pragma: no-cache');
        header('Expires: 0');
        header('Cache-Control: must-revalidate, post-check=0, pre-check=0');

        // Open output stream
        $output = fopen('php://output', 'w');

        if ($output === false) {
            wp_die(__('Failed to open output stream.', 'wc-top-spenders'));
        }

        // Add UTF-8 BOM for Excel compatibility
        fprintf($output, chr(0xEF).chr(0xBB).chr(0xBF));

        // Add CSV headers
        fputcsv($output, ['Name', 'Email', 'Phone Number', 'Total Spend']);

        // Add data rows
        foreach ($data as $row) {
            if (!is_array($row)) {
                continue;
            }

            fputcsv($output, [
                isset($row['name']) ? $row['name'] : '',
                isset($row['email']) ? $row['email'] : '',
                isset($row['phone']) ? $row['phone'] : 'N/A',
                isset($row['total_spent']) ? number_format($row['total_spent'], 2, '.', '') : '0.00'
            ]);
        }

        fclose($output);
        exit;
    }

    private function get_statistics() {
        global $wpdb;

        try {
            // All registered users
            $total_customers = $wpdb->get_var("SELECT COUNT(ID) FROM {$wpdb->users}");

            if ($wpdb->last_error) {
                return new WP_Error('db_error', $wpdb->last_error);
            }

            // Get total completed orders
            $total_orders = $wpdb->get_var("
                SELECT COUNT(*)
                FROM {$wpdb->posts}
                WHERE post_type = 'shop_order'
                AND post_status IN ('wc-completed', 'wc-processing')
            ");

            if ($wpdb->last_error) {
                return new WP_Error('db_error', $wpdb->last_error);
            }

            // Get total revenue
            $total_revenue = $wpdb->get_var("
                SELECT SUM(CAST(pm.meta_value AS DECIMAL(10,2)))
                FROM {$wpdb->posts} p
                INNER JOIN {$wpdb->postmeta} pm
                    ON p.ID = pm.post_id
                    AND pm.meta_key = '_order_total'
                WHERE p.post_type = 'shop_order'
                AND p.post_status IN ('wc-completed', 'wc-processing')
            ");

            if ($wpdb->last_error) {
                return new WP_Error('db_error', $wpdb->last_error);
            }

            return [
                'total_customers' => intval($total_customers),
                'total_orders' => intval($total_orders),
                'total_revenue' => floatval($total_revenue)
            ];
        } catch (Exception $e) {
            return new WP_Error('db_exception', $e->getMessage());
        }
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
                <p><strong><?php _e('WooCommerce Top Spenders Export', 'wc-top-spenders'); ?></strong> <?php _e('requires WooCommerce to be installed and active.', 'wc-top-spenders'); ?></p>
            </div>
            <?php
        });
    }
});
