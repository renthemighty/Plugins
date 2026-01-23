<?php
/**
 * Plugin Name: WooCommerce Minimum Order
 * Plugin URI: https://github.com/renthemighty/Plugins
 * Description: Set a minimum order threshold and display a notice on checkout if not met
 * Version: 1.0.0
 * Author: Megatron
 * Author URI: https://github.com/renthemighty
 * Requires at least: 5.0
 * Tested up to: 6.4
 * Requires PHP: 7.2
 * WC requires at least: 5.0
 * WC tested up to: 8.5
 * License: GPL v2 or later
 * License URI: https://www.gnu.org/licenses/gpl-2.0.html
 * Text Domain: wc-minimum-order
 */

defined('ABSPATH') || exit;

class WC_Minimum_Order {

    private static $instance = null;

    public static function instance() {
        if (null === self::$instance) {
            self::$instance = new self();
        }
        return self::$instance;
    }

    private function __construct() {
        // Add settings to WooCommerce Advanced tab
        add_filter('woocommerce_get_settings_advanced', [$this, 'add_settings'], 10, 2);
        add_filter('woocommerce_get_sections_advanced', [$this, 'add_section']);

        // Checkout validation
        add_action('woocommerce_review_order_before_payment', [$this, 'display_minimum_order_notice']);
        add_action('woocommerce_checkout_process', [$this, 'validate_minimum_order']);

        // Hide payment buttons with CSS/JS when threshold not met
        add_action('wp_footer', [$this, 'hide_payment_buttons_script']);
    }

    /**
     * Add "Minimum Price" section to Advanced settings
     */
    public function add_section($sections) {
        $sections['minimum-price'] = __('Minimum Price', 'wc-minimum-order');
        return $sections;
    }

    /**
     * Add settings to the Minimum Price section
     */
    public function add_settings($settings, $current_section) {
        if ('minimum-price' !== $current_section) {
            return $settings;
        }

        $custom_settings = [
            [
                'title' => __('Minimum Order Settings', 'wc-minimum-order'),
                'type'  => 'title',
                'desc'  => __('Configure the minimum order threshold for checkout.', 'wc-minimum-order'),
                'id'    => 'wc_minimum_order_settings'
            ],
            [
                'title'    => __('Enable Minimum Order', 'wc-minimum-order'),
                'desc'     => __('Enable minimum order requirement', 'wc-minimum-order'),
                'id'       => 'wc_minimum_order_enabled',
                'default'  => 'yes',
                'type'     => 'checkbox',
            ],
            [
                'title'    => __('Minimum Order Amount', 'wc-minimum-order'),
                'desc'     => __('Set the minimum order amount required for checkout (excluding tax and shipping).', 'wc-minimum-order'),
                'id'       => 'wc_minimum_order_amount',
                'default'  => '0',
                'type'     => 'number',
                'custom_attributes' => [
                    'step' => '0.01',
                    'min'  => '0'
                ]
            ],
            [
                'title'    => __('Notice Message', 'wc-minimum-order'),
                'desc'     => __('Custom message to display when minimum is not met. Use {amount} for the minimum amount.', 'wc-minimum-order'),
                'id'       => 'wc_minimum_order_message',
                'default'  => 'Minimum {amount}',
                'type'     => 'text',
            ],
            [
                'type' => 'sectionend',
                'id'   => 'wc_minimum_order_settings'
            ]
        ];

        return $custom_settings;
    }

    /**
     * Check if cart meets minimum order requirement
     */
    private function meets_minimum() {
        $enabled = get_option('wc_minimum_order_enabled', 'yes');
        if ('yes' !== $enabled) {
            return true;
        }

        $minimum = floatval(get_option('wc_minimum_order_amount', 0));
        if ($minimum <= 0) {
            return true;
        }

        if (!WC()->cart) {
            return true;
        }

        $cart_total = WC()->cart->get_subtotal();

        return $cart_total >= $minimum;
    }

    /**
     * Get the minimum amount
     */
    private function get_minimum_amount() {
        return floatval(get_option('wc_minimum_order_amount', 0));
    }

    /**
     * Display notice on checkout page
     */
    public function display_minimum_order_notice() {
        if ($this->meets_minimum()) {
            return;
        }

        $minimum = $this->get_minimum_amount();
        $message = get_option('wc_minimum_order_message', 'Minimum {amount}');
        $formatted_amount = wc_price($minimum);

        $notice = str_replace('{amount}', $formatted_amount, $message);

        echo '<div id="wc-minimum-order-notice" class="woocommerce-info" style="background:#e74c3c;color:white;padding:15px;margin-bottom:20px;border-radius:5px;text-align:center;font-size:16px;font-weight:bold;">';
        echo esc_html($notice);
        echo '</div>';
    }

    /**
     * Validate minimum order on checkout
     */
    public function validate_minimum_order() {
        if ($this->meets_minimum()) {
            return;
        }

        $minimum = $this->get_minimum_amount();
        $message = get_option('wc_minimum_order_message', 'Minimum {amount}');
        $formatted_amount = wc_price($minimum);

        $notice = str_replace('{amount}', $formatted_amount, $message);

        wc_add_notice($notice, 'error');
    }

    /**
     * Hide payment buttons with JavaScript when minimum not met
     */
    public function hide_payment_buttons_script() {
        if (!is_checkout() || is_order_received_page()) {
            return;
        }

        if ($this->meets_minimum()) {
            return;
        }

        ?>
        <script type="text/javascript">
        jQuery(function($) {
            // Hide payment section
            $('#payment').hide();

            // Also hide the place order button if it exists outside payment
            $('#place_order').hide();
            $('.woocommerce-checkout-payment').hide();

            // Listen for cart updates and re-check
            $(document.body).on('updated_checkout', function() {
                // After checkout update, check if notice still exists
                if ($('#wc-minimum-order-notice').length > 0) {
                    $('#payment').hide();
                    $('#place_order').hide();
                    $('.woocommerce-checkout-payment').hide();
                } else {
                    $('#payment').show();
                    $('#place_order').show();
                    $('.woocommerce-checkout-payment').show();
                }
            });
        });
        </script>
        <style>
        #wc-minimum-order-notice {
            animation: pulse 2s infinite;
        }
        @keyframes pulse {
            0%, 100% { opacity: 1; }
            50% { opacity: 0.8; }
        }
        </style>
        <?php
    }
}

// Initialize
add_action('plugins_loaded', function() {
    if (class_exists('WooCommerce')) {
        WC_Minimum_Order::instance();
    }
});
