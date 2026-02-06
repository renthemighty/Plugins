<?php
/**
 * Plugin Name: WooCommerce Local Shipping Labels
 * Plugin URI: https://github.com/renthemighty/Plugins
 * Description: Generates local shipping labels for WooCommerce orders with barcode, tracking number, and printable label format.
 * Version: 1.0.0
 * Author: Megatron
 * Author URI: https://github.com/renthemighty
 * Requires at least: 5.0
 * Tested up to: 6.7
 * Requires PHP: 7.4
 * WC requires at least: 5.0
 * WC tested up to: 9.5
 * License: GPL v2 or later
 * License URI: https://www.gnu.org/licenses/gpl-2.0.html
 * Text Domain: wc-local-shipping-labels
 */

defined('ABSPATH') || exit;

class WC_Local_Shipping_Labels {

    private static $instance = null;

    const VERSION = '1.0.0';

    public static function instance() {
        if (null === self::$instance) {
            self::$instance = new self();
        }
        return self::$instance;
    }

    private function __construct() {
        // Admin settings
        add_filter('woocommerce_get_sections_shipping', [$this, 'add_settings_section']);
        add_filter('woocommerce_get_settings_shipping', [$this, 'add_settings'], 10, 2);

        // Order list column
        add_filter('manage_edit-shop_order_columns', [$this, 'add_order_column']);
        add_filter('manage_woocommerce_page_wc-orders_columns', [$this, 'add_order_column']);
        add_action('manage_shop_order_posts_custom_column', [$this, 'render_order_column'], 10, 2);
        add_action('manage_woocommerce_page_wc-orders_custom_column', [$this, 'render_order_column_hpos'], 10, 2);

        // Label endpoint
        add_action('admin_init', [$this, 'handle_label_request']);

        // Admin styles
        add_action('admin_enqueue_scripts', [$this, 'enqueue_admin_assets']);

    }

    /**
     * Add settings section under WooCommerce > Settings > Shipping
     */
    public function add_settings_section($sections) {
        $sections['local_shipping_labels'] = __('Local Shipping Labels', 'wc-local-shipping-labels');
        return $sections;
    }

    /**
     * Add settings fields
     */
    public function add_settings($settings, $current_section) {
        if ('local_shipping_labels' !== $current_section) {
            return $settings;
        }

        return [
            [
                'title' => __('Local Shipping Label Settings', 'wc-local-shipping-labels'),
                'type'  => 'title',
                'desc'  => __('Configure sender information and label options for local shipping labels.', 'wc-local-shipping-labels'),
                'id'    => 'wc_lsl_settings',
            ],
            [
                'title'   => __('Sender Name / Store Name', 'wc-local-shipping-labels'),
                'id'      => 'wc_lsl_sender_name',
                'type'    => 'text',
                'default' => "Berry's Bear Bar's",
                'desc'    => __('Business or store name to appear on the label.', 'wc-local-shipping-labels'),
            ],
            [
                'title'   => __('Sender Phone', 'wc-local-shipping-labels'),
                'id'      => 'wc_lsl_sender_phone',
                'type'    => 'text',
                'default' => '',
            ],
            [
                'title'   => __('Sender Address', 'wc-local-shipping-labels'),
                'id'      => 'wc_lsl_sender_address',
                'type'    => 'text',
                'default' => '',
                'desc'    => __('Street address.', 'wc-local-shipping-labels'),
            ],
            [
                'title'   => __('Sender City, Province/State, Postal Code', 'wc-local-shipping-labels'),
                'id'      => 'wc_lsl_sender_city_line',
                'type'    => 'text',
                'default' => '',
                'desc'    => __('e.g. WHITE ROCK, BC V4B 2L1', 'wc-local-shipping-labels'),
            ],
            [
                'type' => 'sectionend',
                'id'   => 'wc_lsl_settings',
            ],
        ];
    }

    /**
     * Add "Shipping Label" column to orders list
     */
    public function add_order_column($columns) {
        $new_columns = [];
        foreach ($columns as $key => $value) {
            $new_columns[$key] = $value;
            if ($key === 'order_status') {
                $new_columns['shipping_label'] = __('Shipping Label', 'wc-local-shipping-labels');
            }
        }
        // If order_status wasn't found, append at end
        if (!isset($new_columns['shipping_label'])) {
            $new_columns['shipping_label'] = __('Shipping Label', 'wc-local-shipping-labels');
        }
        return $new_columns;
    }

    /**
     * Render column content for legacy (CPT) orders
     */
    public function render_order_column($column, $post_id) {
        if ('shipping_label' !== $column) {
            return;
        }
        $this->output_label_button($post_id);
    }

    /**
     * Render column content for HPOS orders
     */
    public function render_order_column_hpos($column, $order) {
        if ('shipping_label' !== $column) {
            return;
        }
        $order_id = is_object($order) ? $order->get_id() : $order;
        $this->output_label_button($order_id);
    }

    /**
     * Output the print label button
     */
    private function output_label_button($order_id) {
        $url = admin_url('admin.php?wc_lsl_print_label=' . $order_id . '&_wpnonce=' . wp_create_nonce('wc_lsl_label_' . $order_id));
        $tracking = get_post_meta($order_id, '_wc_lsl_tracking_number', true);
        if (!$tracking && function_exists('wc_get_order')) {
            $order = wc_get_order($order_id);
            if ($order) {
                $tracking = $order->get_meta('_wc_lsl_tracking_number');
            }
        }

        echo '<a href="' . esc_url($url) . '" target="_blank" class="button wc-lsl-print-btn" title="' . esc_attr__('Print Shipping Label', 'wc-local-shipping-labels') . '">';
        echo '&#128438; ' . esc_html__('Print Label', 'wc-local-shipping-labels');
        echo '</a>';

        if ($tracking) {
            echo '<br><small style="color:#666; font-size:11px;">' . esc_html($tracking) . '</small>';
        }
    }

    /**
     * Enqueue admin CSS for the orders page
     */
    public function enqueue_admin_assets($hook) {
        $screen = get_current_screen();
        if ($screen && (
            $screen->id === 'edit-shop_order' ||
            $screen->id === 'woocommerce_page_wc-orders'
        )) {
            wp_add_inline_style('woocommerce_admin_styles', '
                .column-shipping_label { width: 140px; text-align: center; }
                .wc-lsl-print-btn { font-size: 12px !important; padding: 2px 8px !important; }
            ');
        }
    }

    /**
     * Handle label print request
     */
    public function handle_label_request() {
        if (!isset($_GET['wc_lsl_print_label'])) {
            return;
        }

        $order_id = absint($_GET['wc_lsl_print_label']);
        if (!$order_id) {
            return;
        }

        if (!isset($_GET['_wpnonce']) || !wp_verify_nonce($_GET['_wpnonce'], 'wc_lsl_label_' . $order_id)) {
            wp_die(__('Security check failed.', 'wc-local-shipping-labels'));
        }

        if (!current_user_can('edit_shop_orders')) {
            wp_die(__('You do not have permission to view this label.', 'wc-local-shipping-labels'));
        }

        $order = wc_get_order($order_id);
        if (!$order) {
            wp_die(__('Order not found.', 'wc-local-shipping-labels'));
        }

        // Generate tracking number if not exists
        $tracking = $order->get_meta('_wc_lsl_tracking_number');
        if (!$tracking) {
            $tracking = $this->generate_tracking_number();
            $order->update_meta_data('_wc_lsl_tracking_number', $tracking);
            $order->save();
        }

        // Gather label data
        $data = $this->get_label_data($order, $tracking);

        // Render label
        $this->render_label($data);
        exit;
    }

    /**
     * Generate a random tracking number in format: 1Z XXX XXX XX XXXX XXXX
     */
    public function generate_tracking_number() {
        $chars = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ';

        // Generate: 1Z XXX XXX XX XXXX XXXX
        $part1 = '';
        for ($i = 0; $i < 3; $i++) {
            $part1 .= $chars[wp_rand(0, strlen($chars) - 1)];
        }
        $part2 = '';
        for ($i = 0; $i < 3; $i++) {
            $part2 .= $chars[wp_rand(0, strlen($chars) - 1)];
        }
        $part3 = '';
        for ($i = 0; $i < 2; $i++) {
            $part3 .= $chars[wp_rand(0, strlen($chars) - 1)];
        }
        $part4 = '';
        for ($i = 0; $i < 4; $i++) {
            $part4 .= wp_rand(0, 9);
        }
        $part5 = '';
        for ($i = 0; $i < 4; $i++) {
            $part5 .= wp_rand(0, 9);
        }

        return "1Z {$part1} {$part2} {$part3} {$part4} {$part5}";
    }

    /**
     * Build label data array from order
     */
    private function get_label_data($order, $tracking) {
        $order_id = $order->get_id();
        $order_number = str_pad($order_id, 6, '0', STR_PAD_LEFT);

        // Sender info from settings
        $sender_name    = get_option('wc_lsl_sender_name', get_bloginfo('name'));
        $sender_phone   = get_option('wc_lsl_sender_phone', '');
        $sender_address = get_option('wc_lsl_sender_address', '');
        $sender_city    = get_option('wc_lsl_sender_city_line', '');

        // Recipient info from order
        $ship_name = trim($order->get_shipping_first_name() . ' ' . $order->get_shipping_last_name());
        if (empty(trim($ship_name))) {
            $ship_name = trim($order->get_billing_first_name() . ' ' . $order->get_billing_last_name());
        }

        $ship_address_1 = $order->get_shipping_address_1();
        $ship_address_2 = $order->get_shipping_address_2();
        if (empty($ship_address_1)) {
            $ship_address_1 = $order->get_billing_address_1();
            $ship_address_2 = $order->get_billing_address_2();
        }

        $ship_city    = $order->get_shipping_city() ?: $order->get_billing_city();
        $ship_state   = $order->get_shipping_state() ?: $order->get_billing_state();
        $ship_zip     = $order->get_shipping_postcode() ?: $order->get_billing_postcode();
        $ship_country = $order->get_shipping_country() ?: $order->get_billing_country();
        $ship_phone   = $order->get_shipping_phone();
        if (empty($ship_phone)) {
            $ship_phone = $order->get_billing_phone();
        }

        $full_address = $ship_address_1;
        if (!empty($ship_address_2)) {
            $full_address .= ', ' . $ship_address_2;
        }

        $city_line = strtoupper(trim("{$ship_city} {$ship_state} {$ship_zip}"));

        return [
            'order_id'        => $order_id,
            'order_number'    => $order_number,
            'hi_code'         => "HI {$order_number} RT1",
            'tracking'        => $tracking,
            'sender_name'     => strtoupper($sender_name),
            'sender_phone'    => $sender_phone,
            'sender_address'  => strtoupper($sender_address),
            'sender_city'     => strtoupper($sender_city),
            'ship_name'       => strtoupper($ship_name),
            'ship_address'    => strtoupper($full_address),
            'ship_city_line'  => $city_line,
            'ship_phone'      => $ship_phone,
        ];
    }

    /**
     * Render the shipping label HTML page
     */
    private function render_label($data) {
        // Load template
        include plugin_dir_path(__FILE__) . 'templates/label.php';
    }
}

// Initialize
add_action('plugins_loaded', function () {
    if (class_exists('WooCommerce')) {
        WC_Local_Shipping_Labels::instance();
    }
});

// Declare HPOS compatibility
add_action('before_woocommerce_init', function () {
    if (class_exists('\Automattic\WooCommerce\Utilities\FeaturesUtil')) {
        \Automattic\WooCommerce\Utilities\FeaturesUtil::declare_compatibility('custom_order_tables', __FILE__, true);
    }
});
