<?php
/**
 * Plugin Name: WooCommerce LiteSpeed Country Cache
 * Plugin URI: https://github.com/renthemighty/Plugins
 * Description: Ensures LiteSpeed Cache serves correct pages per country for Country Based Restrictions PRO. Varies cache by country and purges on country change.
 * Version: 1.0.0
 * Author: Megatron
 * Author URI: https://github.com/renthemighty
 * Requires at least: 5.0
 * Tested up to: 6.7
 * Requires PHP: 7.2
 * WC requires at least: 5.0
 * WC tested up to: 9.5
 * License: GPL v2 or later
 * License URI: https://www.gnu.org/licenses/gpl-2.0.html
 * Text Domain: wc-litespeed-country-cache
 */

defined('ABSPATH') || exit;

class WC_LiteSpeed_Country_Cache {

    private static $instance = null;

    const COOKIE_NAME = 'wc_country';
    const VERSION     = '1.0.0';

    public static function instance() {
        if (null === self::$instance) {
            self::$instance = new self();
        }
        return self::$instance;
    }

    private function __construct() {
        // ── Core: Set country cookie early on every page load ──
        add_action('template_redirect', [$this, 'sync_country_cookie'], 5);
        add_action('woocommerce_set_cart_cookies', [$this, 'sync_country_cookie']);

        // ── LiteSpeed integration: Tell LS to vary cache by our cookie ──
        add_action('litespeed_init', [$this, 'register_litespeed_vary']);
        add_filter('litespeed_vary_cookies', [$this, 'add_vary_cookie']);

        // ── Fallback: If LiteSpeed vary isn't enough, add Vary header directly ──
        add_action('send_headers', [$this, 'send_vary_header']);

        // ── AJAX endpoint for frontend country changes ──
        add_action('wp_ajax_wc_lscc_country_change', [$this, 'ajax_country_change']);
        add_action('wp_ajax_nopriv_wc_lscc_country_change', [$this, 'ajax_country_change']);

        // ── Frontend JS ──
        add_action('wp_enqueue_scripts', [$this, 'enqueue_scripts']);

        // ── Hook into WooCommerce country changes (server-side) ──
        add_action('woocommerce_checkout_update_order_review', [$this, 'on_checkout_country_update']);
        add_action('woocommerce_customer_save_address', [$this, 'on_address_save'], 10, 2);

        // ── Admin settings ──
        add_filter('woocommerce_get_settings_advanced', [$this, 'add_settings'], 10, 2);
        add_filter('woocommerce_get_sections_advanced', [$this, 'add_section']);

        // ── HQPC: Declare WooCommerce feature compatibility ──
        add_action('before_woocommerce_init', [$this, 'declare_hpos_compatibility']);
    }

    // =====================================================================
    //  COUNTRY COOKIE SYNC
    // =====================================================================

    /**
     * Detect the customer's current WooCommerce country and set a cookie.
     * LiteSpeed uses this cookie to serve the correct cached page per country.
     */
    public function sync_country_cookie() {
        if (is_admin() || wp_doing_cron() || (defined('DOING_AJAX') && DOING_AJAX)) {
            return;
        }

        $country = $this->get_customer_country();
        if (!$country) {
            return;
        }

        $current = isset($_COOKIE[self::COOKIE_NAME]) ? sanitize_text_field($_COOKIE[self::COOKIE_NAME]) : '';

        if ($current !== $country) {
            $this->set_country_cookie($country);
        }
    }

    /**
     * Determine customer's country from WooCommerce data.
     */
    private function get_customer_country() {
        // Priority 1: WooCommerce customer object (session-based, most accurate)
        if (function_exists('WC') && WC()->customer) {
            $country = WC()->customer->get_shipping_country();
            if ($country) return $country;

            $country = WC()->customer->get_billing_country();
            if ($country) return $country;
        }

        // Priority 2: WooCommerce session data
        if (function_exists('WC') && WC()->session) {
            $customer_data = WC()->session->get('customer');
            if (!empty($customer_data['shipping_country'])) {
                return $customer_data['shipping_country'];
            }
            if (!empty($customer_data['country'])) {
                return $customer_data['country'];
            }
        }

        // Priority 3: Geolocation
        if (class_exists('WC_Geolocation')) {
            $location = WC_Geolocation::geolocate_ip();
            if (!empty($location['country'])) {
                return $location['country'];
            }
        }

        // Priority 4: WooCommerce default country
        $default = get_option('woocommerce_default_country', '');
        if ($default) {
            $parts = explode(':', $default);
            return $parts[0];
        }

        return '';
    }

    /**
     * Set the country cookie.
     */
    private function set_country_cookie($country) {
        $country = sanitize_text_field($country);
        setcookie(
            self::COOKIE_NAME,
            $country,
            [
                'expires'  => time() + DAY_IN_SECONDS,
                'path'     => COOKIEPATH ?: '/',
                'domain'   => COOKIE_DOMAIN ?: '',
                'secure'   => is_ssl(),
                'httponly'  => false, // JS needs to read this
                'samesite'  => 'Lax',
            ]
        );
        $_COOKIE[self::COOKIE_NAME] = $country;
    }

    // =====================================================================
    //  LITESPEED CACHE INTEGRATION
    // =====================================================================

    /**
     * Register our cookie as a vary key with LiteSpeed.
     * This tells LiteSpeed to cache separate versions per country.
     */
    public function register_litespeed_vary() {
        // Use LiteSpeed Cache API if available
        if (method_exists('LiteSpeed\Vary', 'cls')) {
            do_action('litespeed_vary_append', self::COOKIE_NAME);
        }
    }

    /**
     * Filter: Add our cookie to the LiteSpeed vary cookies list.
     */
    public function add_vary_cookie($cookies) {
        if (!is_array($cookies)) {
            $cookies = [];
        }
        if (!in_array(self::COOKIE_NAME, $cookies, true)) {
            $cookies[] = self::COOKIE_NAME;
        }
        return $cookies;
    }

    /**
     * Fallback: Send a Vary header so any cache layer respects the cookie.
     */
    public function send_vary_header() {
        if (is_admin() || headers_sent()) {
            return;
        }
        header('Vary: Cookie', false);
    }

    /**
     * Purge LiteSpeed cache when country changes.
     */
    private function purge_litespeed_cache() {
        $purge_mode = get_option('wc_lscc_purge_mode', 'smart');

        if ($purge_mode === 'all') {
            // Nuclear option: purge everything
            if (has_action('litespeed_purge_all')) {
                do_action('litespeed_purge_all');
            }
        } else {
            // Smart purge: only purge shop/product pages
            $tags_to_purge = [
                'shop',
                'product',
                'product_cat',
                'archive',
                'frontpage',
                'home',
            ];

            foreach ($tags_to_purge as $tag) {
                if (has_action('litespeed_purge')) {
                    do_action('litespeed_purge', $tag);
                }
            }

            // Also purge the shop page and product archive specifically
            $shop_page_id = wc_get_page_id('shop');
            if ($shop_page_id > 0 && has_action('litespeed_purge_post')) {
                do_action('litespeed_purge_post', $shop_page_id);
            }
        }
    }

    // =====================================================================
    //  AJAX ENDPOINT – Frontend country change handler
    // =====================================================================

    /**
     * Handle AJAX call when user changes country on the frontend.
     */
    public function ajax_country_change() {
        check_ajax_referer('wc_lscc_nonce', 'nonce');

        $new_country = isset($_POST['country']) ? sanitize_text_field($_POST['country']) : '';

        if (empty($new_country) || strlen($new_country) !== 2) {
            wp_send_json_error(['message' => 'Invalid country code.']);
        }

        $old_country = isset($_COOKIE[self::COOKIE_NAME]) ? sanitize_text_field($_COOKIE[self::COOKIE_NAME]) : '';

        // Update the cookie
        $this->set_country_cookie($new_country);

        // Update WooCommerce customer session
        if (function_exists('WC') && WC()->customer) {
            WC()->customer->set_billing_country($new_country);
            WC()->customer->set_shipping_country($new_country);
            WC()->customer->save();
        }

        // Purge LiteSpeed cache if country actually changed
        $purged = false;
        if ($old_country !== $new_country) {
            $this->purge_litespeed_cache();
            $purged = true;
        }

        wp_send_json_success([
            'old_country' => $old_country,
            'new_country' => $new_country,
            'purged'      => $purged,
        ]);
    }

    // =====================================================================
    //  SERVER-SIDE HOOKS – Catch country changes from WooCommerce itself
    // =====================================================================

    /**
     * When checkout order review updates (user changed country dropdown).
     */
    public function on_checkout_country_update($posted_data) {
        parse_str($posted_data, $data);

        $new_country = '';
        if (!empty($data['billing_country'])) {
            $new_country = sanitize_text_field($data['billing_country']);
        } elseif (!empty($data['shipping_country'])) {
            $new_country = sanitize_text_field($data['shipping_country']);
        }

        if (!$new_country) {
            return;
        }

        $old_country = isset($_COOKIE[self::COOKIE_NAME]) ? sanitize_text_field($_COOKIE[self::COOKIE_NAME]) : '';

        if ($old_country !== $new_country) {
            $this->set_country_cookie($new_country);
            $this->purge_litespeed_cache();
        }
    }

    /**
     * When customer saves their address in My Account.
     */
    public function on_address_save($user_id, $address_type) {
        $customer = new WC_Customer($user_id);

        $country = '';
        if ($address_type === 'shipping') {
            $country = $customer->get_shipping_country();
        } else {
            $country = $customer->get_billing_country();
        }

        if (!$country) {
            return;
        }

        $old_country = isset($_COOKIE[self::COOKIE_NAME]) ? sanitize_text_field($_COOKIE[self::COOKIE_NAME]) : '';

        if ($old_country !== $country) {
            $this->set_country_cookie($country);
            $this->purge_litespeed_cache();
        }
    }

    // =====================================================================
    //  FRONTEND SCRIPTS
    // =====================================================================

    /**
     * Enqueue the country-change detection script on frontend pages.
     */
    public function enqueue_scripts() {
        if (is_admin()) {
            return;
        }

        wp_enqueue_script('jquery');

        // Pass data to JS via localized object
        wp_localize_script('jquery', 'wc_lscc', [
            'ajax_url'         => admin_url('admin-ajax.php'),
            'nonce'            => wp_create_nonce('wc_lscc_nonce'),
            'current_country'  => isset($_COOKIE[self::COOKIE_NAME]) ? sanitize_text_field($_COOKIE[self::COOKIE_NAME]) : '',
            'reload_on_change' => get_option('wc_lscc_reload', 'yes'),
        ]);

        add_action('wp_footer', [$this, 'inline_script'], 99);
    }

    /**
     * Output the inline JS that detects country selector changes.
     */
    public function inline_script() {
        ?>
        <script type="text/javascript">
        (function($) {
            if (typeof wc_lscc === 'undefined') return;

            var currentCountry = wc_lscc.current_country || '';
            var debounceTimer = null;

            /**
             * Send the new country to the server, update cookie, purge cache.
             */
            function onCountryChange(newCountry) {
                if (!newCountry || newCountry.length !== 2 || newCountry === currentCountry) {
                    return;
                }

                // Clear any pending debounce
                if (debounceTimer) clearTimeout(debounceTimer);

                debounceTimer = setTimeout(function() {
                    $.ajax({
                        url: wc_lscc.ajax_url,
                        type: 'POST',
                        data: {
                            action: 'wc_lscc_country_change',
                            nonce: wc_lscc.nonce,
                            country: newCountry
                        },
                        success: function(response) {
                            if (response.success && response.data.purged) {
                                currentCountry = newCountry;

                                // Set cookie on client side too for immediate effect
                                document.cookie = '<?php echo esc_js(self::COOKIE_NAME); ?>=' +
                                    newCountry + ';path=/;max-age=86400;SameSite=Lax';

                                // Reload the page so the new country restrictions take effect
                                if (wc_lscc.reload_on_change === 'yes') {
                                    // Add a cache-busting parameter to ensure fresh load
                                    var url = new URL(window.location.href);
                                    url.searchParams.set('lscc', newCountry);
                                    window.location.href = url.toString();
                                }
                            }
                        }
                    });
                }, 500); // 500ms debounce
            }

            // ── Listen to WooCommerce country selectors ──

            // Billing country on checkout
            $(document.body).on('change', '#billing_country, select[name="billing_country"]', function() {
                onCountryChange($(this).val());
            });

            // Shipping country on checkout
            $(document.body).on('change', '#shipping_country, select[name="shipping_country"]', function() {
                onCountryChange($(this).val());
            });

            // Country Based Restrictions PRO country selector (various selectors it may use)
            $(document.body).on('change', '.wcbcr-country-select, #wcbcr_country, select[name="wcbcr_country"], .country-selector select, #country-switch select', function() {
                onCountryChange($(this).val());
            });

            // WooCommerce cart shipping calculator country
            $(document.body).on('change', '#calc_shipping_country', function() {
                onCountryChange($(this).val());
            });

            // WooCommerce country_to_state_changed event
            $(document.body).on('country_to_state_changed', function(e, country) {
                if (typeof country === 'string' && country.length === 2) {
                    onCountryChange(country);
                }
            });

            // Also watch for the WooCommerce update_checkout trigger
            $(document.body).on('update_checkout', function() {
                var bc = $('#billing_country').val();
                var sc = $('#shipping_country').val();
                onCountryChange(sc || bc);
            });

            // ── Clean up cache-bust parameter after page load ──
            if (window.location.search.indexOf('lscc=') !== -1) {
                var cleanUrl = new URL(window.location.href);
                cleanUrl.searchParams.delete('lscc');
                window.history.replaceState({}, document.title, cleanUrl.toString());
            }

        })(jQuery);
        </script>
        <?php
    }

    // =====================================================================
    //  ADMIN SETTINGS (under WooCommerce > Settings > Advanced)
    // =====================================================================

    /**
     * Add a "LiteSpeed Country Cache" section.
     */
    public function add_section($sections) {
        $sections['litespeed-country'] = __('LiteSpeed Country Cache', 'wc-litespeed-country-cache');
        return $sections;
    }

    /**
     * Settings fields.
     */
    public function add_settings($settings, $current_section) {
        if ('litespeed-country' !== $current_section) {
            return $settings;
        }

        return [
            [
                'title' => __('LiteSpeed Country Cache Settings', 'wc-litespeed-country-cache'),
                'type'  => 'title',
                'desc'  => __(
                    'Configure how LiteSpeed Cache handles country-based content. ' .
                    'This plugin ensures pages are cached separately per country so that ' .
                    'Country Based Restrictions PRO works correctly with LiteSpeed Cache.',
                    'wc-litespeed-country-cache'
                ),
                'id'    => 'wc_lscc_settings',
            ],
            [
                'title'   => __('Purge Mode', 'wc-litespeed-country-cache'),
                'desc'    => __(
                    'Smart purge clears only shop/product pages. Full purge clears the entire cache.',
                    'wc-litespeed-country-cache'
                ),
                'id'      => 'wc_lscc_purge_mode',
                'default' => 'smart',
                'type'    => 'select',
                'options' => [
                    'smart' => __('Smart (shop & product pages only)', 'wc-litespeed-country-cache'),
                    'all'   => __('Full (purge entire cache)', 'wc-litespeed-country-cache'),
                ],
            ],
            [
                'title'   => __('Reload Page on Country Change', 'wc-litespeed-country-cache'),
                'desc'    => __(
                    'Automatically reload the page when a user changes country, ' .
                    'so they immediately see the correct product restrictions.',
                    'wc-litespeed-country-cache'
                ),
                'id'      => 'wc_lscc_reload',
                'default' => 'yes',
                'type'    => 'select',
                'options' => [
                    'yes' => __('Yes - Reload page (recommended)', 'wc-litespeed-country-cache'),
                    'no'  => __('No - Do not reload', 'wc-litespeed-country-cache'),
                ],
            ],
            [
                'type' => 'sectionend',
                'id'   => 'wc_lscc_settings',
            ],
        ];
    }

    // =====================================================================
    //  WOOCOMMERCE COMPATIBILITY
    // =====================================================================

    /**
     * Declare HPOS compatibility.
     */
    public function declare_hpos_compatibility() {
        if (class_exists(\Automattic\WooCommerce\Utilities\FeaturesUtil::class)) {
            \Automattic\WooCommerce\Utilities\FeaturesUtil::declare_compatibility(
                'custom_order_tables',
                __FILE__,
                true
            );
        }
    }
}

// ── Initialize ──
add_action('plugins_loaded', function() {
    if (class_exists('WooCommerce')) {
        WC_LiteSpeed_Country_Cache::instance();
    }
});
