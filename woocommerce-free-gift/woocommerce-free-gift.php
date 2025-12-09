<?php
/**
 * Plugin Name: WooCommerce Free Gift
 * Plugin URI: https://github.com/renthemighty/Plugins
 * Description: Automatically add a free gift product to every order
 * Version: 1.0.9
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

// Prevent multiple loads
if (defined('WC_FREE_GIFT_LOADED')) {
    return;
}
define('WC_FREE_GIFT_LOADED', true);

// Define plugin constants
if (!defined('WC_FREE_GIFT_VERSION')) {
    define('WC_FREE_GIFT_VERSION', '1.0.9');
}
if (!defined('WC_FREE_GIFT_PLUGIN_DIR')) {
    define('WC_FREE_GIFT_PLUGIN_DIR', plugin_dir_path(__FILE__));
}
if (!defined('WC_FREE_GIFT_PLUGIN_URL')) {
    define('WC_FREE_GIFT_PLUGIN_URL', plugin_dir_url(__FILE__));
}

// Only define the class if it doesn't exist
if (!class_exists('WC_Free_Gift')) {

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
            // Always add admin menu
            add_action('admin_menu', array($this, 'add_admin_menu'));
            add_action('admin_init', array($this, 'register_settings'));
            add_action('admin_enqueue_scripts', array($this, 'enqueue_admin_scripts'));

            // Initialize functionality on plugins_loaded
            add_action('plugins_loaded', array($this, 'init'));
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

            // Add free gift to cart - multiple hooks for maximum reliability
            add_action('wp_loaded', array($this, 'maybe_add_free_gift'));
            add_action('woocommerce_before_calculate_totals', array($this, 'add_free_gift_to_cart'), 10, 1);
            add_action('woocommerce_cart_loaded_from_session', array($this, 'add_free_gift_to_cart'), 10, 1);

            // Ensure free gift stays free even after discount plugins
            add_filter('woocommerce_cart_item_price', array($this, 'ensure_free_gift_price'), 999, 3);
            add_filter('woocommerce_cart_item_subtotal', array($this, 'ensure_free_gift_price'), 999, 3);

            // Prevent removal of free gift
            add_filter('woocommerce_cart_item_remove_link', array($this, 'disable_free_gift_removal'), 10, 2);

            // Add free gift message
            add_filter('woocommerce_cart_item_name', array($this, 'add_free_gift_label'), 10, 3);

            // Persist free gift cart data
            add_filter('woocommerce_add_cart_item_data', array($this, 'add_free_gift_cart_item_data'), 10, 3);
            add_filter('woocommerce_get_cart_item_from_session', array($this, 'get_free_gift_from_session'), 10, 2);
        }

        /**
         * Enqueue admin scripts
         */
        public function enqueue_admin_scripts($hook) {
            if ('toplevel_page_wc-free-gift' !== $hook) {
                return;
            }
            wp_enqueue_script('selectWoo');
            wp_enqueue_style('woocommerce_admin_styles');
        }

        /**
         * Maybe add free gift on wp_loaded
         */
        public function maybe_add_free_gift() {
            if (!function_exists('WC') || !WC()->cart) {
                return;
            }
            $this->add_free_gift_to_cart(WC()->cart);
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
                'manage_options',
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
            if (!current_user_can('manage_options')) {
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

            // Get current product for display
            $current_product_name = '';
            if ($current_product_id > 0) {
                $current_product = wc_get_product($current_product_id);
                if ($current_product) {
                    $current_product_name = $current_product->get_name();
                }
            }
            ?>
            <div class="wrap">
                <h1><?php echo esc_html(get_admin_page_title()); ?></h1>

                <div style="background: #fff; padding: 20px; margin-top: 20px; border: 1px solid #ccd0d4; box-shadow: 0 1px 1px rgba(0,0,0,.04);">
                    <h2><?php _e('Configure Your Free Gift', 'wc-free-gift'); ?></h2>
                    <p><?php _e('Search and select the product that will be automatically added as a free gift to every order.', 'wc-free-gift'); ?></p>

                    <form method="post" action="">
                        <?php wp_nonce_field('wc_free_gift_save', 'wc_free_gift_nonce'); ?>

                        <table class="form-table" role="presentation">
                            <tbody>
                                <tr>
                                    <th scope="row">
                                        <label for="wc_free_gift_product_id"><?php _e('Free Gift Product', 'wc-free-gift'); ?></label>
                                    </th>
                                    <td>
                                        <select name="wc_free_gift_product_id" id="wc_free_gift_product_id" class="wc-product-search" style="width: 50%;" data-placeholder="<?php esc_attr_e('Search for a product&hellip;', 'wc-free-gift'); ?>" data-allow_clear="true">
                                            <?php if ($current_product_id > 0 && !empty($current_product_name)): ?>
                                                <option value="<?php echo esc_attr($current_product_id); ?>" selected="selected">
                                                    <?php echo esc_html($current_product_name); ?> (ID: <?php echo $current_product_id; ?>)
                                                </option>
                                            <?php else: ?>
                                                <option value="0"><?php _e('-- Select a Product --', 'wc-free-gift'); ?></option>
                                            <?php endif; ?>
                                        </select>
                                        <p class="description">
                                            <?php _e('Type to search for products. This product will be added to every cart automatically at no charge.', 'wc-free-gift'); ?>
                                        </p>
                                    </td>
                                </tr>
                            </tbody>
                        </table>

                        <?php submit_button(__('Save Settings', 'wc-free-gift')); ?>
                    </form>

                    <script type="text/javascript">
                        jQuery(document).ready(function($) {
                            $('#wc_free_gift_product_id').selectWoo({
                                ajax: {
                                    url: ajaxurl,
                                    dataType: 'json',
                                    delay: 250,
                                    data: function(params) {
                                        return {
                                            term: params.term,
                                            action: 'woocommerce_json_search_products',
                                            security: '<?php echo wp_create_nonce('search-products'); ?>'
                                        };
                                    },
                                    processResults: function(data) {
                                        var results = [];
                                        $.each(data, function(id, text) {
                                            results.push({
                                                id: id,
                                                text: text
                                            });
                                        });
                                        return {
                                            results: results
                                        };
                                    },
                                    cache: true
                                },
                                minimumInputLength: 1
                            });
                        });
                    </script>

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
            // Prevent infinite loops with static flag
            static $running = false;
            if ($running) {
                return;
            }
            $running = true;

            // Make sure we have a cart object
            if (!$cart || !is_object($cart)) {
                if (function_exists('WC') && WC()->cart) {
                    $cart = WC()->cart;
                } else {
                    $running = false;
                    return;
                }
            }

            // Get the free gift product ID
            $free_gift_id = get_option('wc_free_gift_product_id', 0);

            // Debug output
            if (current_user_can('manage_options')) {
                echo '<!-- DEBUG: Free Gift ID=' . $free_gift_id . ' -->';
            }

            // If no product is selected, do nothing
            if (empty($free_gift_id) || $free_gift_id <= 0) {
                $running = false;
                return;
            }

            // Verify product exists
            $product = wc_get_product($free_gift_id);
            if (!$product) {
                if (current_user_can('manage_options')) {
                    echo '<!-- DEBUG: Product not found -->';
                }
                $running = false;
                return;
            }

            // Check if the free gift is already in the cart
            $free_gift_in_cart = false;
            $has_regular_items = false;
            $free_gift_key = null;

            foreach ($cart->get_cart() as $cart_item_key => $cart_item) {
                // Check if this is our free gift
                if ($cart_item['product_id'] == $free_gift_id) {
                    $free_gift_in_cart = true;
                    $free_gift_key = $cart_item_key;
                    // Set price to 0
                    $cart_item['data']->set_price(0);
                    // Mark it as a free gift
                    $cart->cart_contents[$cart_item_key]['free_gift'] = true;
                } else {
                    // This is a regular item (not the free gift)
                    if (!isset($cart_item['free_gift']) || !$cart_item['free_gift']) {
                        $has_regular_items = true;
                    }
                }
            }

            if (current_user_can('manage_options')) {
                echo '<!-- DEBUG: In cart=' . ($free_gift_in_cart ? 'yes' : 'no') . ' Has regular=' . ($has_regular_items ? 'yes' : 'no') . ' -->';
            }

            // If free gift is not in cart and there are regular items, add it
            if (!$free_gift_in_cart && $has_regular_items) {
                // Add the free gift to cart
                $added = $cart->add_to_cart(
                    $free_gift_id,  // product_id
                    1,              // quantity
                    0,              // variation_id
                    array(),        // variation
                    array('free_gift' => true)  // cart_item_data
                );

                if (current_user_can('manage_options')) {
                    echo '<!-- DEBUG: Add result=' . ($added ? $added : 'FAILED') . ' -->';
                }

                // If successfully added, set price to 0
                if ($added) {
                    foreach ($cart->get_cart() as $cart_item_key => $cart_item) {
                        if ($cart_item_key === $added && isset($cart_item['free_gift'])) {
                            $cart_item['data']->set_price(0);
                        }
                    }
                }
            }

            // If there are no regular items and free gift is in cart, remove it
            if (!$has_regular_items && $free_gift_in_cart && $free_gift_key) {
                $cart->remove_cart_item($free_gift_key);
            }

            $running = false;
        }

        /**
         * Ensure free gift displays as free
         */
        public function ensure_free_gift_price($price, $cart_item, $cart_item_key) {
            if (isset($cart_item['free_gift']) && $cart_item['free_gift']) {
                return wc_price(0);
            }
            return $price;
        }

        /**
         * Disable removal link for free gift items
         */
        public function disable_free_gift_removal($link, $cart_item_key) {
            global $woocommerce;
            $cart = $woocommerce->cart->get_cart();

            if (isset($cart[$cart_item_key]['free_gift']) && $cart[$cart_item_key]['free_gift']) {
                return '';
            }
            return $link;
        }

        /**
         * Add "Free Gift" label to product name in cart
         */
        public function add_free_gift_label($name, $cart_item, $cart_item_key) {
            if (isset($cart_item['free_gift']) && $cart_item['free_gift']) {
                $name .= ' <span style="background: #4CAF50; color: white; padding: 2px 8px; border-radius: 3px; font-size: 11px; font-weight: bold; margin-left: 8px;">' . __('FREE GIFT', 'wc-free-gift') . '</span>';
            }
            return $name;
        }

        /**
         * Add free gift data when adding to cart
         */
        public function add_free_gift_cart_item_data($cart_item_data, $product_id, $variation_id) {
            $free_gift_id = get_option('wc_free_gift_product_id', 0);
            if ($product_id == $free_gift_id && isset($cart_item_data['free_gift'])) {
                $cart_item_data['free_gift'] = true;
                $cart_item_data['unique_key'] = md5(microtime().rand());
            }
            return $cart_item_data;
        }

        /**
         * Get free gift data from session
         */
        public function get_free_gift_from_session($cart_item, $values) {
            if (isset($values['free_gift']) && $values['free_gift']) {
                $cart_item['free_gift'] = true;
                $cart_item['data']->set_price(0);
            }
            return $cart_item;
        }
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
