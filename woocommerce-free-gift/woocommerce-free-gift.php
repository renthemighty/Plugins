<?php
/**
 * Plugin Name: WooCommerce Free Gift
 * Plugin URI: https://github.com/renthemighty/Plugins
 * Description: Automatically add a free gift product to every order
 * Version: 2.0.5
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

defined('ABSPATH') || exit;

class WC_Free_Gift_Simple {

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
        add_action('admin_init', [$this, 'register_setting']);
        add_action('admin_enqueue_scripts', [$this, 'admin_scripts']);
        add_action('wp_ajax_wc_free_gift_load_variations', [$this, 'ajax_load_variations']);

        // Cart functionality - simple and direct
        add_action('template_redirect', [$this, 'check_and_add_gift'], 99);
        add_action('woocommerce_add_to_cart', [$this, 'on_add_to_cart'], 10);
        add_action('woocommerce_cart_item_removed', [$this, 'on_cart_item_removed'], 10);
        add_filter('woocommerce_add_to_cart_validation', [$this, 'prevent_gift_manual_add'], 10, 2);
        add_filter('woocommerce_cart_item_remove_link', [$this, 'remove_gift_remove_link'], 10, 2);
        add_filter('woocommerce_cart_item_name', [$this, 'add_gift_badge'], 10, 3);
        add_filter('woocommerce_cart_item_quantity', [$this, 'set_gift_quantity'], 10, 3);
        add_action('woocommerce_before_calculate_totals', [$this, 'set_gift_price'], 999);
        add_action('woocommerce_after_cart_item_quantity_update', [$this, 'enforce_gift_quantity'], 10, 2);
        add_filter('woocommerce_update_cart_validation', [$this, 'validate_cart_update'], 10, 4);
        add_filter('woocommerce_cart_item_class', [$this, 'add_gift_cart_class'], 10, 2);
        add_action('wp_head', [$this, 'add_gift_styles']);
    }

    public function admin_menu() {
        add_menu_page(
            'Free Gift Settings',
            'Free Gift',
            'manage_options',
            'wc-free-gift',
            [$this, 'settings_page'],
            'dashicons-gift',
            56
        );
    }

    public function register_setting() {
        register_setting('wc_free_gift', 'wc_free_gift_product_id');
    }

    public function admin_scripts($hook) {
        if ('toplevel_page_wc-free-gift' !== $hook) return;
        wp_enqueue_script('selectWoo');
        wp_enqueue_style('woocommerce_admin_styles');
    }

    public function ajax_load_variations() {
        check_ajax_referer('load-variations', 'security');

        $product_id = absint($_POST['product_id'] ?? 0);
        $product = wc_get_product($product_id);
        $variations = [];

        if ($product && $product->is_type('variable')) {
            $available_variations = $product->get_available_variations();
            foreach ($available_variations as $variation) {
                $variation_obj = wc_get_product($variation['variation_id']);
                $variations[] = [
                    'id' => $variation['variation_id'],
                    'name' => $variation_obj->get_name()
                ];
            }
        }

        wp_send_json_success($variations);
    }

    public function settings_page() {
        if (!current_user_can('manage_options')) return;

        $product_id = get_option('wc_free_gift_product_id', 0);

        if (isset($_POST['wc_free_gift_nonce'])) {
            check_admin_referer('wc_free_gift_save', 'wc_free_gift_nonce');
            $product_id = absint($_POST['wc_free_gift_product_id'] ?? 0);
            $variation_id = absint($_POST['wc_free_gift_variation_id'] ?? 0);
            update_option('wc_free_gift_product_id', $product_id);
            update_option('wc_free_gift_variation_id', $variation_id);
            echo '<div class="notice notice-success"><p>Settings saved!</p></div>';
        }

        $variation_id = absint(get_option('wc_free_gift_variation_id', 0));
        $product_name = '';
        $variation_name = '';
        if ($product_id > 0) {
            $product = wc_get_product($product_id);
            if ($product) $product_name = $product->get_name();
        }
        if ($variation_id > 0) {
            $variation = wc_get_product($variation_id);
            if ($variation) $variation_name = $variation->get_name();
        }
        ?>
        <div class="wrap">
            <h1>Free Gift Settings</h1>
            <form method="post">
                <?php wp_nonce_field('wc_free_gift_save', 'wc_free_gift_nonce'); ?>
                <table class="form-table">
                    <tr>
                        <th>Select Free Gift Product</th>
                        <td>
                            <select name="wc_free_gift_product_id" id="wc_free_gift_product_id" style="width:400px">
                                <?php if ($product_id > 0 && $product_name): ?>
                                    <option value="<?php echo $product_id; ?>" selected><?php echo esc_html($product_name); ?> (ID: <?php echo $product_id; ?>)</option>
                                <?php else: ?>
                                    <option value="0">-- Select Product --</option>
                                <?php endif; ?>
                            </select>
                            <p class="description">Search and select a product to add as free gift</p>
                        </td>
                    </tr>
                    <tr id="variation_row" style="<?php echo ($product_id > 0) ? '' : 'display:none;'; ?>">
                        <th>Select Variation (Optional)</th>
                        <td>
                            <select name="wc_free_gift_variation_id" id="wc_free_gift_variation_id" style="width:400px">
                                <?php if ($variation_id > 0 && $variation_name): ?>
                                    <option value="<?php echo $variation_id; ?>" selected><?php echo esc_html($variation_name); ?> (ID: <?php echo $variation_id; ?>)</option>
                                <?php else: ?>
                                    <option value="0">-- Select Variation --</option>
                                <?php endif; ?>
                            </select>
                            <p class="description">If the product has variations, select one here</p>
                        </td>
                    </tr>
                </table>
                <?php submit_button(); ?>
            </form>
            <script>
            jQuery(function($) {
                $('#wc_free_gift_product_id').selectWoo({
                    ajax: {
                        url: ajaxurl,
                        dataType: 'json',
                        data: function(params) {
                            return {
                                term: params.term,
                                action: 'woocommerce_json_search_products',
                                security: '<?php echo wp_create_nonce('search-products'); ?>'
                            };
                        },
                        processResults: function(data) {
                            return { results: Object.keys(data).map(id => ({id: id, text: data[id]})) };
                        }
                    },
                    minimumInputLength: 1
                }).on('change', function() {
                    var productId = $(this).val();
                    if (productId > 0) {
                        loadVariations(productId);
                        $('#variation_row').show();
                    } else {
                        $('#variation_row').hide();
                    }
                });

                function loadVariations(productId) {
                    $.post(ajaxurl, {
                        action: 'wc_free_gift_load_variations',
                        product_id: productId,
                        security: '<?php echo wp_create_nonce('load-variations'); ?>'
                    }, function(response) {
                        if (response.success && response.data.length > 0) {
                            var $select = $('#wc_free_gift_variation_id');
                            $select.empty().append('<option value="0">-- Select Variation --</option>');
                            $.each(response.data, function(i, variation) {
                                $select.append('<option value="' + variation.id + '">' + variation.name + '</option>');
                            });
                        }
                    });
                }
            });
            </script>
        </div>
        <?php
    }

    public function check_and_add_gift() {
        if (!function_exists('WC') || !WC()->cart) return;
        if (is_admin()) return;

        $cart = WC()->cart;
        if ($cart->is_empty()) return;

        $gift_id = absint(get_option('wc_free_gift_product_id', 0));
        $variation_id = absint(get_option('wc_free_gift_variation_id', 0));
        if ($gift_id <= 0) return;

        // Check if gift already in cart
        foreach ($cart->get_cart() as $key => $item) {
            if ($variation_id > 0) {
                // For variations, check variation_id
                if ($item['variation_id'] == $variation_id && isset($item['free_gift'])) {
                    return; // Already there
                }
            } else {
                // For simple products, check product_id
                if ($item['product_id'] == $gift_id && isset($item['free_gift'])) {
                    return; // Already there
                }
            }
        }

        // Add it
        if ($variation_id > 0) {
            // Add variation
            $variation = wc_get_product($variation_id);
            if ($variation) {
                $attributes = $variation->get_variation_attributes();
                $cart->add_to_cart($gift_id, 1, $variation_id, $attributes, ['free_gift' => true]);
            }
        } else {
            // Add simple product
            $cart->add_to_cart($gift_id, 1, 0, [], ['free_gift' => true]);
        }
    }

    public function on_add_to_cart() {
        $this->check_and_add_gift();
    }

    public function on_cart_item_removed() {
        if (!function_exists('WC') || !WC()->cart) return;

        $cart = WC()->cart;
        $gift_id = absint(get_option('wc_free_gift_product_id', 0));
        $variation_id = absint(get_option('wc_free_gift_variation_id', 0));
        if ($gift_id <= 0) return;

        // Check if there are any regular (non-gift) items
        $has_regular_items = false;
        $gift_key = null;

        foreach ($cart->get_cart() as $key => $item) {
            // Check if this is the free gift
            $is_free_gift = false;
            if ($variation_id > 0) {
                $is_free_gift = ($item['variation_id'] == $variation_id && isset($item['free_gift']));
            } else {
                $is_free_gift = ($item['product_id'] == $gift_id && isset($item['free_gift']));
            }

            if ($is_free_gift) {
                $gift_key = $key;
            } else {
                $has_regular_items = true;
            }
        }

        // If no regular items and gift is in cart, remove it
        if (!$has_regular_items && $gift_key) {
            $cart->remove_cart_item($gift_key);
        }
    }

    public function prevent_gift_manual_add($valid, $product_id) {
        // Prevent manual addition of the gift product
        $gift_id = absint(get_option('wc_free_gift_product_id', 0));
        if ($gift_id > 0 && $product_id == $gift_id) {
            wc_add_notice('This product is automatically added as a free gift and cannot be purchased separately.', 'error');
            return false;
        }
        return $valid;
    }

    public function remove_gift_remove_link($link, $cart_item_key) {
        $cart = WC()->cart->get_cart();
        if (isset($cart[$cart_item_key]['free_gift'])) {
            return ''; // No remove link
        }
        return $link;
    }

    public function add_gift_badge($name, $cart_item, $cart_item_key) {
        if (isset($cart_item['free_gift'])) {
            $name .= ' <span style="background:#4CAF50;color:white;padding:3px 8px;border-radius:3px;font-size:11px;margin-left:8px;">FREE GIFT</span>';
        }
        return $name;
    }

    public function set_gift_quantity($quantity, $cart_item_key, $cart_item) {
        // Make free gift quantity non-editable (display as plain text)
        if (isset($cart_item['free_gift'])) {
            return sprintf('<span class="gift-quantity">%s</span>', $cart_item['quantity']);
        }
        return $quantity;
    }

    public function enforce_gift_quantity($cart_item_key, $quantity) {
        if (!function_exists('WC') || !WC()->cart) return;

        $cart = WC()->cart->get_cart();
        if (isset($cart[$cart_item_key]['free_gift'])) {
            // Force free gift quantity to always be 1
            WC()->cart->cart_contents[$cart_item_key]['quantity'] = 1;
        }
    }

    public function validate_cart_update($passed, $cart_item_key, $values, $quantity) {
        // Prevent quantity updates for free gift items
        if (isset($values['free_gift']) && $quantity != 1) {
            wc_add_notice('The free gift quantity cannot be changed.', 'error');
            return false;
        }
        return $passed;
    }

    public function set_gift_price($cart) {
        foreach ($cart->get_cart() as $key => $item) {
            if (isset($item['free_gift'])) {
                $item['data']->set_price(0);
            }
        }
    }

    public function add_gift_cart_class($class, $cart_item) {
        if (isset($cart_item['free_gift'])) {
            $class .= ' free-gift-item';
        }
        return $class;
    }

    public function add_gift_styles() {
        echo '<style>
            .free-gift-item .quantity input { display: none !important; }
            .free-gift-item .quantity { pointer-events: none !important; }
        </style>';
    }
}

// Initialize
add_action('plugins_loaded', function() {
    if (class_exists('WooCommerce')) {
        WC_Free_Gift_Simple::instance();
    }
});
