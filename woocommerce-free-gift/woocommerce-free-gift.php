<?php
/**
 * Plugin Name: WooCommerce Free Gift
 * Plugin URI: https://github.com/renthemighty/Plugins
 * Description: Automatically add a free gift product to every order
 * Version: 1.0.1
 * Author: SPVS
 * Author URI: https://github.com/renthemighty
 * Requires at least: 5.0
 * Tested up to: 6.4
 * Requires PHP: 7.2
 * WC requires at least: 5.0
 * WC tested up to: 8.5
 * License: GPL v2 or later
 * License URI: https://www.gnu.org/licenses/gpl-2.0.html
 * Text Domain: wc-free-gift
 */

// Exit if accessed directly
if (!defined('ABSPATH')) {
    exit;
}

/**
 * Main WooCommerce Free Gift Class
 */
class WC_Free_Gift {

    /**
     * Single instance of the class
     */
    private static $instance = null;

    /**
     * Get single instance
     */
    public static function get_instance() {
        if (self::$instance === null) {
            self::$instance = new self();
        }
        return self::$instance;
    }

    /**
     * Constructor
     */
    private function __construct() {
        $this->define_constants();
        add_action('plugins_loaded', array($this, 'init'));
    }

    /**
     * Define plugin constants
     */
    private function define_constants() {
        if (!defined('WC_FREE_GIFT_VERSION')) {
            define('WC_FREE_GIFT_VERSION', '1.0.1');
        }
        if (!defined('WC_FREE_GIFT_PLUGIN_DIR')) {
            define('WC_FREE_GIFT_PLUGIN_DIR', plugin_dir_path(__FILE__));
        }
        if (!defined('WC_FREE_GIFT_PLUGIN_URL')) {
            define('WC_FREE_GIFT_PLUGIN_URL', plugin_dir_url(__FILE__));
        }
    }

    /**
     * Initialize the plugin
     */
    public function init() {
        // Check if WooCommerce is active
        if (!class_exists('WooCommerce')) {
            add_action('admin_notices', array($this, 'woocommerce_missing_notice'));
            return;
        }

        // Load admin functionality
        if (is_admin()) {
            add_action('admin_menu', array($this, 'add_admin_menu'));
            add_action('admin_init', array($this, 'register_settings'));
        }

        // Add free gift to cart - Use late priority to run after other plugins
        add_action('woocommerce_before_calculate_totals', array($this, 'add_free_gift_to_cart'), 999, 1);

        // Ensure free gift stays free even after discount plugins
        add_filter('woocommerce_cart_item_price', array($this, 'ensure_free_gift_price'), 999, 3);
        add_filter('woocommerce_cart_item_subtotal', array($this, 'ensure_free_gift_price'), 999, 3);
    }

    /**
     * Notice if WooCommerce is not active
     */
    public function woocommerce_missing_notice() {
        ?>
        <div class="notice notice-error">
            <p><?php _e('WooCommerce Free Gift requires WooCommerce to be installed and active.', 'wc-free-gift'); ?></p>
        </div>
        <?php
    }

    /**
     * Add admin menu
     */
    public function add_admin_menu() {
        add_menu_page(
            __('Free Gift Settings', 'wc-free-gift'),
            __('Free Gift', 'wc-free-gift'),
            'manage_woocommerce',
            'wc-free-gift',
            array($this, 'render_admin_page'),
            'dashicons-gift',
            56
        );
    }

    /**
     * Register settings
     */
    public function register_settings() {
        register_setting('wc_free_gift_settings', 'wc_free_gift_product_id', array(
            'type' => 'integer',
            'default' => 0,
            'sanitize_callback' => 'absint'
        ));
    }

    /**
     * Render admin settings page
     */
    public function render_admin_page() {
        // Check user capabilities
        if (!current_user_can('manage_woocommerce')) {
            return;
        }

        // Get current setting
        $current_product_id = get_option('wc_free_gift_product_id', 0);

        // Handle form submission
        if (isset($_POST['wc_free_gift_nonce']) && wp_verify_nonce($_POST['wc_free_gift_nonce'], 'wc_free_gift_save')) {
            $product_id = isset($_POST['wc_free_gift_product_id']) ? absint($_POST['wc_free_gift_product_id']) : 0;
            update_option('wc_free_gift_product_id', $product_id);
            $current_product_id = $product_id;
            echo '<div class="notice notice-success is-dismissible"><p>' . __('Settings saved successfully!', 'wc-free-gift') . '</p></div>';
        }

        // Get all products for dropdown
        $args = array(
            'post_type' => 'product',
            'posts_per_page' => -1,
            'post_status' => 'publish',
            'orderby' => 'title',
            'order' => 'ASC'
        );
        $products = get_posts($args);
        ?>
        <div class="wrap">
            <h1><?php echo esc_html(get_admin_page_title()); ?></h1>

            <div style="background: #fff; padding: 20px; margin-top: 20px; border: 1px solid #ccd0d4; box-shadow: 0 1px 1px rgba(0,0,0,.04);">
                <h2><?php _e('Configure Your Free Gift', 'wc-free-gift'); ?></h2>
                <p><?php _e('Select the product that will be automatically added as a free gift to every order.', 'wc-free-gift'); ?></p>

                <form method="post" action="">
                    <?php wp_nonce_field('wc_free_gift_save', 'wc_free_gift_nonce'); ?>

                    <table class="form-table" role="presentation">
                        <tbody>
                            <tr>
                                <th scope="row">
                                    <label for="wc_free_gift_product_id"><?php _e('Free Gift Product', 'wc-free-gift'); ?></label>
                                </th>
                                <td>
                                    <select name="wc_free_gift_product_id" id="wc_free_gift_product_id" class="regular-text">
                                        <option value="0"><?php _e('-- Select a Product --', 'wc-free-gift'); ?></option>
                                        <?php foreach ($products as $product): ?>
                                            <option value="<?php echo esc_attr($product->ID); ?>" <?php selected($current_product_id, $product->ID); ?>>
                                                <?php echo esc_html($product->post_title); ?> (ID: <?php echo $product->ID; ?>)
                                            </option>
                                        <?php endforeach; ?>
                                    </select>
                                    <p class="description">
                                        <?php _e('This product will be added to every cart automatically at no charge.', 'wc-free-gift'); ?>
                                    </p>
                                </td>
                            </tr>
                        </tbody>
                    </table>

                    <?php submit_button(__('Save Settings', 'wc-free-gift')); ?>
                </form>

                <?php if ($current_product_id > 0):
                    $product = wc_get_product($current_product_id);
                    if ($product):
                ?>
                <div style="margin-top: 30px; padding-top: 20px; border-top: 1px solid #ccd0d4;">
                    <h3><?php _e('Current Free Gift', 'wc-free-gift'); ?></h3>
                    <div style="display: flex; align-items: center; gap: 20px;">
                        <?php if ($product->get_image_id()): ?>
                            <div>
                                <?php echo $product->get_image('thumbnail'); ?>
                            </div>
                        <?php endif; ?>
                        <div>
                            <p><strong><?php echo esc_html($product->get_name()); ?></strong></p>
                            <p><?php echo wp_kses_post($product->get_short_description()); ?></p>
                            <p><small><?php _e('Product ID:', 'wc-free-gift'); ?> <?php echo $current_product_id; ?></small></p>
                        </div>
                    </div>
                </div>
                <?php
                    endif;
                endif;
                ?>
            </div>

            <div style="background: #fff; padding: 20px; margin-top: 20px; border: 1px solid #ccd0d4; box-shadow: 0 1px 1px rgba(0,0,0,.04);">
                <h3><?php _e('How It Works', 'wc-free-gift'); ?></h3>
                <ul style="list-style: disc; padding-left: 20px;">
                    <li><?php _e('The selected product is automatically added to every customer\'s cart', 'wc-free-gift'); ?></li>
                    <li><?php _e('The product is always added at $0.00 (free)', 'wc-free-gift'); ?></li>
                    <li><?php _e('Works with discount and sales plugins - the free gift stays free', 'wc-free-gift'); ?></li>
                    <li><?php _e('Customers cannot remove the free gift from their cart', 'wc-free-gift'); ?></li>
                    <li><?php _e('Only one free gift is added per order, regardless of cart contents', 'wc-free-gift'); ?></li>
                </ul>
            </div>
        </div>
        <?php
    }

    /**
     * Add free gift to cart
     */
    public function add_free_gift_to_cart($cart) {
        // Skip if we're in admin or doing AJAX (except cart updates)
        if (is_admin() && !defined('DOING_AJAX')) {
            return;
        }

        // Prevent infinite loops
        if (did_action('woocommerce_before_calculate_totals') >= 2) {
            return;
        }

        // Get the free gift product ID
        $free_gift_id = get_option('wc_free_gift_product_id', 0);

        // If no product is selected, do nothing
        if ($free_gift_id <= 0) {
            return;
        }

        // Check if the free gift is already in the cart
        $free_gift_in_cart = false;
        foreach ($cart->get_cart() as $cart_item_key => $cart_item) {
            if ($cart_item['product_id'] == $free_gift_id) {
                $free_gift_in_cart = true;
                // Set price to 0
                $cart_item['data']->set_price(0);
                // Mark it as a free gift
                $cart->cart_contents[$cart_item_key]['free_gift'] = true;
            }
        }

        // If free gift is not in cart and cart is not empty, add it
        if (!$free_gift_in_cart && !$cart->is_empty()) {
            $cart_item_data = array('free_gift' => true);
            $cart->add_to_cart($free_gift_id, 1, 0, array(), $cart_item_data);
        }
    }

    /**
     * Ensure free gift displays as free
     */
    public function ensure_free_gift_price($price, $cart_item, $cart_item_key) {
        if (isset($cart_item['free_gift']) && $cart_item['free_gift']) {
            return wc_price(0) . ' <small class="wc-free-gift-label">' . __('(Free Gift)', 'wc-free-gift') . '</small>';
        }
        return $price;
    }
}

/**
 * Initialize the plugin
 */
function wc_free_gift_init() {
    return WC_Free_Gift::get_instance();
}

// Start the plugin
add_action('plugins_loaded', 'wc_free_gift_init', 10);
