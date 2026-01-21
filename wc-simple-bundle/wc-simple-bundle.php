<?php
/**
 * Plugin Name: WooCommerce Simple Bundle
 * Plugin URI: https://example.com
 * Description: Create bundle products with automatic stock management. Bundle contents display on orders and packing slips.
 * Version: 3.1.2
 * Author: Your Name
 * Author URI: https://example.com
 * Requires at least: 5.8
 * Requires PHP: 7.4
 * WC requires at least: 6.0
 * WC tested up to: 8.0
 * Text Domain: wc-simple-bundle
 * Domain Path: /languages
 *
 * @package WC_Simple_Bundle
 */

defined('ABSPATH') || exit;

/**
 * Main plugin class
 */
final class WC_Simple_Bundle {
    
    /**
     * Plugin version
     */
    const VERSION = '3.1.2';
    
    /**
     * Single instance
     */
    private static $instance = null;
    
    /**
     * Get instance
     */
    public static function instance() {
        if (is_null(self::$instance)) {
            self::$instance = new self();
        }
        return self::$instance;
    }
    
    /**
     * Constructor
     */
    private function __construct() {
        add_action('plugins_loaded', array($this, 'init'));
    }
    
    /**
     * Initialize plugin
     */
    public function init() {
        // Check for WooCommerce
        if (!class_exists('WooCommerce')) {
            add_action('admin_notices', array($this, 'woocommerce_missing_notice'));
            return;
        }
        
        // Load product class
        require_once plugin_dir_path(__FILE__) . 'includes/class-wc-product-bundle.php';
        
        // Register product type
        add_filter('product_type_selector', array($this, 'add_product_type'));
        add_filter('woocommerce_product_class', array($this, 'woocommerce_product_class'), 10, 2);
        
        // Add admin tabs and panels
        add_filter('woocommerce_product_data_tabs', array($this, 'add_product_data_tab'));
        add_action('woocommerce_product_data_panels', array($this, 'add_product_data_panel'));
        
        // Save product data
        add_action('woocommerce_process_product_meta_bundle', array($this, 'save_bundle_data'));
        
        // Admin assets
        add_action('admin_enqueue_scripts', array($this, 'admin_scripts'));
        
        // AJAX handlers
        add_action('wp_ajax_wcsb_search_products', array($this, 'ajax_search_products'));
        
        // Frontend
        add_action('woocommerce_bundle_add_to_cart', 'woocommerce_simple_add_to_cart');
        
        // Stock management
        add_action('woocommerce_reduce_order_stock', array($this, 'reduce_order_stock'));
        add_action('woocommerce_restore_order_stock', array($this, 'restore_order_stock'));

        // Add bundle contents to order items for packing slips
        add_action('woocommerce_checkout_create_order_line_item', array($this, 'add_bundle_contents_to_order_item'), 10, 4);

        // Ensure bundle contents meta is visible
        add_filter('woocommerce_hidden_order_itemmeta', array($this, 'unhide_bundle_contents_meta'));

        // Format bundle contents for display
        add_filter('woocommerce_order_item_display_meta_key', array($this, 'format_bundle_meta_key'), 10, 3);
        add_filter('woocommerce_order_item_display_meta_value', array($this, 'format_bundle_meta_value'), 10, 3);

        // Display bundle contents on PDF packing slips (WP Overnight plugin)
        add_action('wpo_wcpdf_after_item_meta', array($this, 'display_bundle_contents_on_packing_slip'), 10, 3);
    }
    
    /**
     * WooCommerce missing notice
     */
    public function woocommerce_missing_notice() {
        ?>
        <div class="error">
            <p><?php esc_html_e('WooCommerce Simple Bundle requires WooCommerce to be installed and active.', 'wc-simple-bundle'); ?></p>
        </div>
        <?php
    }
    
    /**
     * Add bundle to product type selector
     */
    public function add_product_type($types) {
        $types['bundle'] = __('Bundle', 'wc-simple-bundle');
        return $types;
    }
    
    /**
     * Set the correct product class for bundle products
     */
    public function woocommerce_product_class($classname, $product_type) {
        if ($product_type === 'bundle') {
            $classname = 'WC_Product_Bundle';
        }
        return $classname;
    }
    
    /**
     * Add bundle products tab
     */
    public function add_product_data_tab($tabs) {
        $tabs['bundle'] = array(
            'label'    => __('Bundle Products', 'wc-simple-bundle'),
            'target'   => 'bundle_product_data',
            'class'    => array('show_if_bundle'),
            'priority' => 21,
        );
        return $tabs;
    }
    
    /**
     * Add bundle products panel
     */
    public function add_product_data_panel() {
        global $post;
        
        $product = wc_get_product($post->ID);
        $bundle_data = array();
        
        if ($product && method_exists($product, 'get_bundle_data')) {
            $bundle_data = $product->get_bundle_data();
        }
        
        include plugin_dir_path(__FILE__) . 'views/admin-bundle-panel.php';
    }
    
    /**
     * Save bundle data
     */
    public function save_bundle_data($post_id) {
        $bundle_data = array();
        
        if (isset($_POST['bundle_product_id']) && is_array($_POST['bundle_product_id'])) {
            $product_ids = array_map('intval', $_POST['bundle_product_id']);
            $quantities = isset($_POST['bundle_product_qty']) ? array_map('intval', $_POST['bundle_product_qty']) : array();
            
            foreach ($product_ids as $index => $product_id) {
                if ($product_id > 0) {
                    $bundle_data[] = array(
                        'product_id' => $product_id,
                        'quantity'   => isset($quantities[$index]) ? max(1, $quantities[$index]) : 1,
                    );
                }
            }
        }
        
        update_post_meta($post_id, '_bundle_data', $bundle_data);
    }
    
    /**
     * Enqueue admin scripts
     */
    public function admin_scripts($hook) {
        if ('post.php' !== $hook && 'post-new.php' !== $hook) {
            return;
        }
        
        $screen = get_current_screen();
        
        if (!$screen || 'product' !== $screen->post_type) {
            return;
        }
        
        wp_enqueue_script('jquery-ui-autocomplete');
        
        wp_enqueue_script(
            'wcsb-admin',
            plugin_dir_url(__FILE__) . 'assets/admin.js',
            array('jquery', 'jquery-ui-autocomplete'),
            self::VERSION,
            true
        );
        
        wp_localize_script('wcsb-admin', 'wcsbAdmin', array(
            'ajax_url' => admin_url('admin-ajax.php'),
            'search_nonce' => wp_create_nonce('wcsb_search_products'),
        ));
        
        wp_enqueue_style(
            'wcsb-admin',
            plugin_dir_url(__FILE__) . 'assets/admin.css',
            array(),
            self::VERSION
        );
    }
    
    /**
     * AJAX search for products
     */
    public function ajax_search_products() {
        check_ajax_referer('wcsb_search_products', 'security');
        
        $term = isset($_GET['term']) ? sanitize_text_field($_GET['term']) : '';
        
        if (strlen($term) < 3) {
            wp_send_json(array());
        }
        
        $results = array();
        
        try {
            $data_store = WC_Data_Store::load('product');
            $ids = $data_store->search_products($term, '', true, false, 20);
            
            foreach ($ids as $product_id) {
                $product = wc_get_product($product_id);
                
                if (!$product || $product->get_type() === 'bundle') {
                    continue;
                }
                
                $results[] = array(
                    'id'    => $product_id,
                    'text'  => $product->get_formatted_name(),
                    'label' => $product->get_formatted_name(),
                );
            }
        } catch (Exception $e) {
            $args = array(
                'post_type'      => 'product',
                'post_status'    => 'publish',
                'posts_per_page' => 20,
                's'              => $term,
            );
            
            $products = get_posts($args);
            
            foreach ($products as $post) {
                $product = wc_get_product($post->ID);
                
                if (!$product || $product->get_type() === 'bundle') {
                    continue;
                }
                
                $results[] = array(
                    'id'    => $post->ID,
                    'text'  => $product->get_name() . ' (#' . $post->ID . ')',
                    'label' => $product->get_name() . ' (#' . $post->ID . ')',
                );
            }
        }
        
        wp_send_json($results);
    }
    
    /**
     * Reduce stock levels for bundled products
     */
    public function reduce_order_stock($order) {
        if (!is_a($order, 'WC_Order')) {
            $order = wc_get_order($order);
        }
        
        if (!$order) {
            return;
        }
        
        foreach ($order->get_items() as $item) {
            $product = $item->get_product();
            
            if (!$product || 'bundle' !== $product->get_type()) {
                continue;
            }
            
            $bundle_data = $product->get_bundle_data();
            
            if (empty($bundle_data)) {
                continue;
            }
            
            foreach ($bundle_data as $data) {
                $bundled_product = wc_get_product($data['product_id']);
                
                if (!$bundled_product || !$bundled_product->managing_stock()) {
                    continue;
                }
                
                $qty_to_reduce = $data['quantity'] * $item->get_quantity();
                wc_update_product_stock($bundled_product, $qty_to_reduce, 'decrease');
                
                $order->add_order_note(
                    sprintf(
                        __('Stock reduced for bundled product: %s (-%d)', 'wc-simple-bundle'),
                        $bundled_product->get_name(),
                        $qty_to_reduce
                    )
                );
            }
        }
    }
    
    /**
     * Restore stock levels for bundled products
     */
    public function restore_order_stock($order) {
        if (!is_a($order, 'WC_Order')) {
            $order = wc_get_order($order);
        }
        
        if (!$order) {
            return;
        }
        
        foreach ($order->get_items() as $item) {
            $product = $item->get_product();
            
            if (!$product || 'bundle' !== $product->get_type()) {
                continue;
            }
            
            $bundle_data = $product->get_bundle_data();
            
            if (empty($bundle_data)) {
                continue;
            }
            
            foreach ($bundle_data as $data) {
                $bundled_product = wc_get_product($data['product_id']);
                
                if (!$bundled_product || !$bundled_product->managing_stock()) {
                    continue;
                }
                
                $qty_to_restore = $data['quantity'] * $item->get_quantity();
                wc_update_product_stock($bundled_product, $qty_to_restore, 'increase');
                
                $order->add_order_note(
                    sprintf(
                        __('Stock restored for bundled product: %s (+%d)', 'wc-simple-bundle'),
                        $bundled_product->get_name(),
                        $qty_to_restore
                    )
                );
            }
        }
    }

    /**
     * Add bundle contents to order item metadata
     * This makes the bundled products visible on packing slips
     */
    public function add_bundle_contents_to_order_item($item, $cart_item_key, $values, $order) {
        $product = $item->get_product();

        if (!$product || 'bundle' !== $product->get_type()) {
            return;
        }

        $bundle_data = $product->get_bundle_data();

        if (empty($bundle_data)) {
            return;
        }

        // Build formatted list with line breaks for better display
        $bundle_contents = array();

        foreach ($bundle_data as $data) {
            $bundled_product = wc_get_product($data['product_id']);

            if (!$bundled_product) {
                continue;
            }

            $bundle_contents[] = sprintf(
                '  • %s × %d',
                $bundled_product->get_name(),
                $data['quantity']
            );
        }

        if (!empty($bundle_contents)) {
            // Use line breaks for better readability on packing slips
            $formatted_contents = "\n" . implode("\n", $bundle_contents);
            $item->add_meta_data('_bundle_contents', $formatted_contents, true);
        }
    }

    /**
     * Ensure bundle contents metadata is visible
     */
    public function unhide_bundle_contents_meta($hidden_meta) {
        // Make sure _bundle_contents is not in the hidden meta keys list
        $key = array_search('_bundle_contents', $hidden_meta);
        if ($key !== false) {
            unset($hidden_meta[$key]);
        }
        return $hidden_meta;
    }

    /**
     * Format bundle contents meta key for display
     */
    public function format_bundle_meta_key($display_key, $meta, $item) {
        if ($meta->key === '_bundle_contents') {
            return __('Bundle Contains', 'wc-simple-bundle');
        }
        return $display_key;
    }

    /**
     * Format bundle contents meta value for display
     */
    public function format_bundle_meta_value($display_value, $meta, $item) {
        if ($meta->key === '_bundle_contents') {
            // Preserve line breaks for display
            return nl2br(esc_html($display_value));
        }
        return $display_value;
    }

    /**
     * Display bundle contents on PDF packing slips
     * Hooks into WP Overnight's PDF Invoices & Packing Slips plugin
     */
    public function display_bundle_contents_on_packing_slip($template_type, $item, $order) {
        // Only display on packing slips, not invoices
        if ($template_type !== 'packing-slip') {
            return;
        }

        $product = $item->get_product();

        if (!$product || 'bundle' !== $product->get_type()) {
            return;
        }

        $bundle_data = $product->get_bundle_data();

        if (empty($bundle_data)) {
            return;
        }

        // Output bundle contents with styling
        echo '<div class="bundle-contents" style="margin-top: 5px; padding-left: 10px; font-size: 0.9em; color: #666;">';
        echo '<strong>' . esc_html__('Bundle Contains:', 'wc-simple-bundle') . '</strong><br>';

        foreach ($bundle_data as $data) {
            $bundled_product = wc_get_product($data['product_id']);

            if (!$bundled_product) {
                continue;
            }

            printf(
                '• %s × %d<br>',
                esc_html($bundled_product->get_name()),
                absint($data['quantity'])
            );
        }

        echo '</div>';
    }
}

/**
 * Initialize plugin
 */
function WC_Simple_Bundle() {
    return WC_Simple_Bundle::instance();
}

WC_Simple_Bundle();
