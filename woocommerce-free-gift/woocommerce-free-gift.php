<?php
/**
 * Plugin Name: WooCommerce Free Gift
 * Plugin URI: https://github.com/renthemighty/Plugins
 * Description: Automatically add a free gift product to every order
 * Version: 2.1.3
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
        add_action('wp_ajax_wc_free_gift_search_products', [$this, 'ajax_search_products']);

        // Cart functionality - simple and direct
        add_action('template_redirect', [$this, 'check_and_add_gift'], 99);
        add_action('woocommerce_add_to_cart', [$this, 'on_add_to_cart'], 10);
        add_action('woocommerce_cart_item_removed', [$this, 'on_cart_item_removed'], 10);
        add_filter('woocommerce_add_to_cart_validation', [$this, 'prevent_gift_manual_add'], 10, 2);
        add_filter('woocommerce_cart_item_remove_link', [$this, 'remove_gift_remove_link'], 10, 2);
        add_filter('woocommerce_cart_item_name', [$this, 'add_gift_badge'], 10, 3);
        add_filter('woocommerce_cart_item_quantity', [$this, 'set_gift_quantity'], 10, 3);

        // Multiple hooks to ensure price is ALWAYS $0
        add_action('woocommerce_before_calculate_totals', [$this, 'set_gift_price'], 9999);
        add_action('woocommerce_cart_loaded_from_session', [$this, 'set_gift_price'], 9999);
        add_filter('woocommerce_cart_item_price', [$this, 'display_gift_price'], 9999, 3);
        add_filter('woocommerce_cart_item_subtotal', [$this, 'display_gift_price'], 9999, 3);
        add_action('woocommerce_checkout_create_order_line_item', [$this, 'save_gift_meta_to_order'], 10, 4);
        add_filter('woocommerce_order_item_get_total', [$this, 'enforce_zero_price_order'], 10, 2);

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
                $sku = $variation_obj->get_sku();
                $name = $variation_obj->get_name();

                // Format: Name (SKU: xxx) or just Name if no SKU
                $display_name = $name;
                if ($sku) {
                    $display_name = $name . ' (SKU: ' . $sku . ')';
                }

                $variations[] = [
                    'id' => $variation['variation_id'],
                    'name' => $display_name
                ];
            }
        }

        wp_send_json_success($variations);
    }

    public function ajax_search_products() {
        check_ajax_referer('search-products', 'security');

        $term = sanitize_text_field($_GET['term'] ?? '');
        $results = [];

        if (strlen($term) < 1) {
            wp_send_json($results);
        }

        // Search products by name or SKU
        $args = [
            'post_type' => 'product',
            'posts_per_page' => 50,
            's' => $term,
            'post_status' => 'publish'
        ];

        // Also search by SKU
        $sku_query = new WP_Query([
            'post_type' => 'product',
            'posts_per_page' => 50,
            'post_status' => 'publish',
            'meta_query' => [
                [
                    'key' => '_sku',
                    'value' => $term,
                    'compare' => 'LIKE'
                ]
            ]
        ]);

        $query = new WP_Query($args);
        $product_ids = array_merge($query->posts, $sku_query->posts);
        $product_ids = array_unique(array_map(function($post) { return $post->ID; }, $product_ids));

        foreach ($product_ids as $product_id) {
            $product = wc_get_product($product_id);
            if ($product) {
                $sku = $product->get_sku();
                $name = $product->get_name();

                // Format: Name (SKU: xxx) (ID: xxx)
                $display_name = $name;
                if ($sku) {
                    $display_name = $name . ' (SKU: ' . $sku . ')';
                }
                $display_name .= ' (ID: ' . $product_id . ')';

                $results[$product_id] = $display_name;
            }
        }

        wp_send_json($results);
    }

    public function settings_page() {
        if (!current_user_can('manage_options')) return;

        if (isset($_POST['wc_free_gift_nonce'])) {
            check_admin_referer('wc_free_gift_save', 'wc_free_gift_nonce');

            // Handle clear log (separate action)
            if (isset($_POST['clear_log'])) {
                $this->clear_debug_log();
                echo '<div class="notice notice-success"><p>Debug log cleared!</p></div>';
            } else {
                // Only save settings if not clearing log
                $enabled = isset($_POST['wc_free_gift_enabled']) ? 1 : 0;
                $debug_mode = isset($_POST['wc_free_gift_debug']) ? 1 : 0;
                update_option('wc_free_gift_enabled', $enabled);
                update_option('wc_free_gift_debug', $debug_mode);

                // Save country-based rules
                $rules = [];
                if (isset($_POST['gift_rules']) && is_array($_POST['gift_rules'])) {
                    foreach ($_POST['gift_rules'] as $rule) {
                        $product_id = absint($rule['product_id'] ?? 0);
                        $variation_id = absint($rule['variation_id'] ?? 0);
                        $country = sanitize_text_field($rule['country'] ?? '');

                        if ($product_id > 0 && $country) {
                            $rules[] = [
                                'product_id' => $product_id,
                                'variation_id' => $variation_id,
                                'country' => $country
                            ];
                        }
                    }
                }
                update_option('wc_free_gift_rules', $rules);
                echo '<div class="notice notice-success"><p>Settings saved!</p></div>';
            }
        }

        $enabled = get_option('wc_free_gift_enabled', 1);
        $debug_mode = get_option('wc_free_gift_debug', 0);
        $rules = get_option('wc_free_gift_rules', []);

        // Get WooCommerce countries
        $countries = WC()->countries->get_countries();
        ?>
        <div class="wrap">
            <h1>Free Gift Settings</h1>
            <form method="post" id="wc-free-gift-form">
                <?php wp_nonce_field('wc_free_gift_save', 'wc_free_gift_nonce'); ?>
                <table class="form-table">
                    <tr>
                        <th>Enable Free Gift</th>
                        <td>
                            <label>
                                <input type="checkbox" name="wc_free_gift_enabled" value="1" <?php checked($enabled, 1); ?>>
                                Enable automatic free gift
                            </label>
                            <p class="description">Turn the free gift feature on or off</p>
                        </td>
                    </tr>
                    <tr>
                        <th>Debug Mode</th>
                        <td>
                            <label>
                                <input type="checkbox" name="wc_free_gift_debug" value="1" <?php checked($debug_mode, 1); ?>>
                                Enable debug logging
                            </label>
                            <p class="description">Log debugging information (only visible to administrators). Check debug log below after saving.</p>
                        </td>
                    </tr>
                    <tr>
                        <th>Free Gift Rules</th>
                        <td>
                            <div id="gift-rules-container">
                                <?php if (!empty($rules)): ?>
                                    <?php foreach ($rules as $index => $rule): ?>
                                        <?php
                                        $product = wc_get_product($rule['product_id']);
                                        $product_name = $product ? $product->get_name() : '';
                                        $product_sku = $product ? $product->get_sku() : '';
                                        $product_display = $product_name;
                                        if ($product_sku) {
                                            $product_display = $product_name . ' (SKU: ' . $product_sku . ')';
                                        }
                                        $product_display .= ' (ID: ' . $rule['product_id'] . ')';

                                        $variation_name = '';
                                        $variation_display = '';
                                        if ($rule['variation_id'] > 0) {
                                            $variation = wc_get_product($rule['variation_id']);
                                            $variation_name = $variation ? $variation->get_name() : '';
                                            $variation_sku = $variation ? $variation->get_sku() : '';
                                            $variation_display = $variation_name;
                                            if ($variation_sku) {
                                                $variation_display = $variation_name . ' (SKU: ' . $variation_sku . ')';
                                            }
                                        }
                                        ?>
                                        <div class="gift-rule-row" style="margin-bottom:15px;padding:15px;border:1px solid #ddd;background:#f9f9f9;">
                                            <div style="margin-bottom:10px;">
                                                <label style="display:inline-block;width:120px;font-weight:bold;">Product:</label>
                                                <select name="gift_rules[<?php echo $index; ?>][product_id]" class="gift-product-select" style="width:300px;">
                                                    <option value="<?php echo $rule['product_id']; ?>" selected><?php echo esc_html($product_display); ?></option>
                                                </select>
                                            </div>
                                            <div style="margin-bottom:10px;" class="variation-field" <?php echo $rule['variation_id'] > 0 ? '' : 'style="display:none;"'; ?>>
                                                <label style="display:inline-block;width:120px;font-weight:bold;">Variation:</label>
                                                <select name="gift_rules[<?php echo $index; ?>][variation_id]" class="gift-variation-select" style="width:300px;">
                                                    <?php if ($rule['variation_id'] > 0): ?>
                                                        <option value="<?php echo $rule['variation_id']; ?>" selected><?php echo esc_html($variation_display); ?></option>
                                                    <?php else: ?>
                                                        <option value="0">-- No Variation --</option>
                                                    <?php endif; ?>
                                                </select>
                                            </div>
                                            <div style="margin-bottom:10px;">
                                                <label style="display:inline-block;width:120px;font-weight:bold;">Country:</label>
                                                <select name="gift_rules[<?php echo $index; ?>][country]" class="gift-country-select" style="width:300px;">
                                                    <?php foreach ($countries as $code => $name): ?>
                                                        <option value="<?php echo esc_attr($code); ?>" <?php selected($rule['country'], $code); ?>><?php echo esc_html($name); ?></option>
                                                    <?php endforeach; ?>
                                                </select>
                                            </div>
                                            <button type="button" class="button remove-rule" style="color:#a00;">Remove</button>
                                        </div>
                                    <?php endforeach; ?>
                                <?php endif; ?>
                            </div>
                            <button type="button" id="add-rule" class="button button-secondary">+ Add Free Gift Rule</button>
                            <p class="description">Add different free gifts for different countries</p>
                        </td>
                    </tr>
                </table>
                <?php submit_button(); ?>
            </form>

            <?php if ($debug_mode && current_user_can('manage_options')): ?>
                <hr style="margin: 30px 0;">
                <h2>Debug Log</h2>
                <p><em>Only visible to administrators when debug mode is enabled.</em></p>
                <?php
                $debug_log = $this->get_debug_log();
                if (!empty($debug_log)):
                ?>
                    <form method="post" style="margin-bottom:10px;">
                        <?php wp_nonce_field('wc_free_gift_save', 'wc_free_gift_nonce'); ?>
                        <input type="hidden" name="clear_log" value="1">
                        <button type="submit" class="button">Clear Debug Log</button>
                    </form>
                    <div style="background:#f5f5f5;padding:15px;border:1px solid #ddd;max-height:400px;overflow-y:auto;font-family:monospace;font-size:12px;">
                        <?php foreach (array_reverse($debug_log) as $entry): ?>
                            <div style="margin-bottom:10px;padding:8px;background:white;border-left:3px solid #0073aa;">
                                <strong><?php echo esc_html($entry['time']); ?></strong><br>
                                <?php echo esc_html($entry['message']); ?><br>
                                <small style="color:#666;">User ID: <?php echo $entry['user_id']; ?> | IP: <?php echo esc_html($entry['ip']); ?></small>
                            </div>
                        <?php endforeach; ?>
                    </div>
                <?php else: ?>
                    <p><em>No debug log entries yet. Add items to cart to see debug information.</em></p>
                <?php endif; ?>
            <?php endif; ?>

            <script>
            jQuery(function($) {
                var ruleIndex = <?php echo count($rules); ?>;
                var countries = <?php echo json_encode($countries); ?>;

                // Initialize existing select2 fields
                initializeSelect2();

                function initializeSelect2() {
                    $('.gift-product-select').each(function() {
                        if (!$(this).hasClass('select2-hidden-accessible')) {
                            $(this).selectWoo({
                                ajax: {
                                    url: ajaxurl,
                                    dataType: 'json',
                                    data: function(params) {
                                        return {
                                            term: params.term,
                                            action: 'wc_free_gift_search_products',
                                            security: '<?php echo wp_create_nonce('search-products'); ?>'
                                        };
                                    },
                                    processResults: function(data) {
                                        return { results: Object.keys(data).map(id => ({id: id, text: data[id]})) };
                                    }
                                },
                                minimumInputLength: 1
                            }).on('change', function() {
                                var $row = $(this).closest('.gift-rule-row');
                                var productId = $(this).val();
                                if (productId > 0) {
                                    loadVariations(productId, $row);
                                }
                            });
                        }
                    });

                    $('.gift-country-select').each(function() {
                        if (!$(this).hasClass('select2-hidden-accessible')) {
                            $(this).selectWoo();
                        }
                    });
                }

                function loadVariations(productId, $row) {
                    $.post(ajaxurl, {
                        action: 'wc_free_gift_load_variations',
                        product_id: productId,
                        security: '<?php echo wp_create_nonce('load-variations'); ?>'
                    }, function(response) {
                        if (response.success && response.data.length > 0) {
                            var $variationField = $row.find('.variation-field');
                            var $select = $row.find('.gift-variation-select');
                            $variationField.show();
                            $select.empty().append('<option value="0">-- No Variation --</option>');
                            $.each(response.data, function(i, variation) {
                                $select.append('<option value="' + variation.id + '">' + variation.name + '</option>');
                            });
                        }
                    });
                }

                // Add new rule
                $('#add-rule').on('click', function() {
                    var countryOptions = '';
                    $.each(countries, function(code, name) {
                        countryOptions += '<option value="' + code + '">' + name + '</option>';
                    });

                    var html = '<div class="gift-rule-row" style="margin-bottom:15px;padding:15px;border:1px solid #ddd;background:#f9f9f9;">' +
                        '<div style="margin-bottom:10px;">' +
                            '<label style="display:inline-block;width:120px;font-weight:bold;">Product:</label>' +
                            '<select name="gift_rules[' + ruleIndex + '][product_id]" class="gift-product-select" style="width:300px;">' +
                                '<option value="0">-- Search for product --</option>' +
                            '</select>' +
                        '</div>' +
                        '<div style="margin-bottom:10px;display:none;" class="variation-field">' +
                            '<label style="display:inline-block;width:120px;font-weight:bold;">Variation:</label>' +
                            '<select name="gift_rules[' + ruleIndex + '][variation_id]" class="gift-variation-select" style="width:300px;">' +
                                '<option value="0">-- No Variation --</option>' +
                            '</select>' +
                        '</div>' +
                        '<div style="margin-bottom:10px;">' +
                            '<label style="display:inline-block;width:120px;font-weight:bold;">Country:</label>' +
                            '<select name="gift_rules[' + ruleIndex + '][country]" class="gift-country-select" style="width:300px;">' +
                                countryOptions +
                            '</select>' +
                        '</div>' +
                        '<button type="button" class="button remove-rule" style="color:#a00;">Remove</button>' +
                    '</div>';

                    $('#gift-rules-container').append(html);
                    ruleIndex++;
                    initializeSelect2();
                });

                // Remove rule
                $(document).on('click', '.remove-rule', function() {
                    $(this).closest('.gift-rule-row').remove();
                });
            });
            </script>
        </div>
        <?php
    }

    public function check_and_add_gift() {
        try {
            if (!function_exists('WC') || !WC()->cart) {
                $this->log_debug('WooCommerce or cart not available');
                return;
            }
            if (is_admin()) return;

            // Check if feature is enabled
            $enabled = get_option('wc_free_gift_enabled', 1);
            if (!$enabled) {
                $this->log_debug('Free gift feature is disabled');
                return;
            }

            $cart = WC()->cart;
            if ($cart->is_empty()) {
                $this->log_debug('Cart is empty, skipping free gift');
                return;
            }

            // Get country-based rules
            $rules = get_option('wc_free_gift_rules', []);
            if (empty($rules)) {
                $this->log_debug('No free gift rules configured');
                return;
            }

            // Detect customer country
            $customer_country = $this->get_customer_country();
            if (!$customer_country) {
                $this->log_debug('Could not detect customer country');
                return;
            }

            $this->log_debug('Customer country detected: ' . $customer_country);

            // Find matching rule for this country
            $matched_rule = null;
            foreach ($rules as $rule) {
                if ($rule['country'] === $customer_country) {
                    $matched_rule = $rule;
                    break;
                }
            }

            if (!$matched_rule) {
                $this->log_debug('No free gift rule found for country: ' . $customer_country);
                return; // Silent - no error for user
            }

            $gift_id = absint($matched_rule['product_id']);
            $variation_id = absint($matched_rule['variation_id']);

            if ($gift_id <= 0) {
                $this->log_debug('Invalid product ID in matched rule');
                return;
            }

            $this->log_debug('Matched rule - Product ID: ' . $gift_id . ', Variation ID: ' . $variation_id);

            // Check if gift already in cart
            foreach ($cart->get_cart() as $key => $item) {
                if ($variation_id > 0) {
                    // For variations, check variation_id
                    if ($item['variation_id'] == $variation_id && isset($item['free_gift'])) {
                        $this->log_debug('Free gift already in cart (variation)');
                        return; // Already there
                    }
                } else {
                    // For simple products, check product_id
                    if ($item['product_id'] == $gift_id && isset($item['free_gift'])) {
                        $this->log_debug('Free gift already in cart (product)');
                        return; // Already there
                    }
                }
            }

            // Add it
            if ($variation_id > 0) {
                // Add variation
                $variation = wc_get_product($variation_id);
                if (!$variation) {
                    $this->log_debug('ERROR: Variation not found - ID: ' . $variation_id);
                    return;
                }
                $attributes = $variation->get_variation_attributes();
                $result = $cart->add_to_cart($gift_id, 1, $variation_id, $attributes, ['free_gift' => true]);
                if ($result) {
                    $this->log_debug('SUCCESS: Added variation to cart - ID: ' . $variation_id);
                } else {
                    $this->log_debug('ERROR: Failed to add variation to cart - ID: ' . $variation_id);
                }
            } else {
                // Add simple product
                $product = wc_get_product($gift_id);
                if (!$product) {
                    $this->log_debug('ERROR: Product not found - ID: ' . $gift_id);
                    return;
                }
                $result = $cart->add_to_cart($gift_id, 1, 0, [], ['free_gift' => true]);
                if ($result) {
                    $this->log_debug('SUCCESS: Added product to cart - ID: ' . $gift_id);
                } else {
                    $this->log_debug('ERROR: Failed to add product to cart - ID: ' . $gift_id);
                }
            }
        } catch (Exception $e) {
            $this->log_debug('EXCEPTION in check_and_add_gift: ' . $e->getMessage());
            // Silent failure - don't show error to customer
        }
    }

    private function get_customer_country() {
        // Priority 1: Try WooCommerce customer billing country (if set)
        if (WC()->customer && method_exists(WC()->customer, 'get_billing_country')) {
            $country = WC()->customer->get_billing_country();
            if ($country) return $country;
        }

        // Priority 2: Try WooCommerce customer shipping country (if set)
        if (WC()->customer && method_exists(WC()->customer, 'get_shipping_country')) {
            $country = WC()->customer->get_shipping_country();
            if ($country) return $country;
        }

        // Priority 3: Try WooCommerce Geolocation (IP-based)
        if (class_exists('WC_Geolocation')) {
            $location = WC_Geolocation::geolocate_ip();
            if (!empty($location['country'])) {
                return $location['country'];
            }
        }

        return false;
    }

    public function on_add_to_cart() {
        $this->check_and_add_gift();
    }

    public function on_cart_item_removed() {
        if (!function_exists('WC') || !WC()->cart) return;

        $cart = WC()->cart;

        // Check if there are any regular (non-gift) items
        $has_regular_items = false;
        $gift_key = null;

        foreach ($cart->get_cart() as $key => $item) {
            if (isset($item['free_gift'])) {
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
        // Prevent manual addition of any gift products
        $rules = get_option('wc_free_gift_rules', []);
        foreach ($rules as $rule) {
            if ($rule['product_id'] == $product_id) {
                wc_add_notice('This product is automatically added as a free gift and cannot be purchased separately.', 'error');
                return false;
            }
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
        if (!$cart) return;

        foreach ($cart->get_cart() as $key => $item) {
            if (isset($item['free_gift'])) {
                // Set price to 0 - multiple times for certainty
                $item['data']->set_price(0);
                $item['data']->set_regular_price(0);
                $item['data']->set_sale_price(0);

                $this->log_debug('Setting free gift price to $0 for cart item: ' . $key);

                // Verify it was set
                if ($item['data']->get_price() != 0) {
                    $this->log_debug('WARNING: Price not zero after setting! Current price: $' . $item['data']->get_price());
                }
            }
        }
    }

    public function display_gift_price($price, $cart_item, $cart_item_key = null) {
        if (isset($cart_item['free_gift'])) {
            $this->log_debug('Displaying free gift price as $0 for cart item');
            return wc_price(0);
        }
        return $price;
    }

    public function save_gift_meta_to_order($item, $cart_item_key, $values, $order) {
        // Save free_gift flag to order item meta
        if (isset($values['free_gift'])) {
            $item->add_meta_data('free_gift', true, true);
            $item->set_total(0);
            $item->set_subtotal(0);
            $this->log_debug('Saved free_gift meta to order item and set price to $0');
        }
    }

    public function enforce_zero_price_order($total, $item) {
        // For order items (after checkout)
        if ($item && is_object($item) && method_exists($item, 'get_meta')) {
            $is_free_gift = $item->get_meta('free_gift', true);
            if ($is_free_gift) {
                $this->log_debug('Enforcing $0 price on order item');
                return 0;
            }
        }
        return $total;
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

    private function log_debug($message) {
        $debug_mode = get_option('wc_free_gift_debug', 0);
        if (!$debug_mode) return;

        $log = get_option('wc_free_gift_debug_log', []);
        $log[] = [
            'time' => current_time('mysql'),
            'message' => $message,
            'user_id' => get_current_user_id(),
            'ip' => $_SERVER['REMOTE_ADDR'] ?? 'unknown'
        ];

        // Keep only last 100 entries
        if (count($log) > 100) {
            $log = array_slice($log, -100);
        }

        update_option('wc_free_gift_debug_log', $log);
    }

    public function get_debug_log() {
        return get_option('wc_free_gift_debug_log', []);
    }

    public function clear_debug_log() {
        delete_option('wc_free_gift_debug_log');
    }
}

// Initialize
add_action('plugins_loaded', function() {
    if (class_exists('WooCommerce')) {
        WC_Free_Gift_Simple::instance();
    }
});
