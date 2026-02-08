<?php
/**
 * Plugin Name: WooCommerce LiteSpeed Country Cache
 * Plugin URI: https://github.com/renthemighty/Plugins
 * Description: Ensures LiteSpeed Cache serves correct pages per country for Country Based Restrictions PRO. Varies cache by the CBR "country" cookie and purges on country change.
 * Version: 1.1.0
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

    /**
     * The cookie name used by Country Based Restrictions PRO.
     * CBR sets this cookie via JS: Cookies.set('country', 'XX')
     * We tell LiteSpeed to vary its cache by this cookie.
     */
    const CBR_COOKIE = 'country';
    const VERSION    = '1.1.0';

    public static function instance() {
        if (null === self::$instance) {
            self::$instance = new self();
        }
        return self::$instance;
    }

    private function __construct() {
        // ── LiteSpeed: Register the CBR "country" cookie as a cache vary key ──
        // Both filters are needed: one registers globally, one for current response
        add_filter('litespeed_vary_cookies', [$this, 'add_vary_cookie']);
        add_filter('litespeed_vary_curr_cookies', [$this, 'add_vary_cookie']);

        // ── Ensure CBR cookie exists on first visit (geolocation fallback) ──
        add_action('template_redirect', [$this, 'ensure_country_cookie'], 5);

        // ── AJAX endpoint: purge cache when country changes ──
        add_action('wp_ajax_wc_lscc_purge', [$this, 'ajax_purge']);
        add_action('wp_ajax_nopriv_wc_lscc_purge', [$this, 'ajax_purge']);

        // ── Server-side: catch country changes from WooCommerce hooks ──
        add_action('woocommerce_checkout_update_order_review', [$this, 'on_checkout_country_update']);
        add_action('woocommerce_customer_save_address', [$this, 'on_address_save'], 10, 2);

        // ── Also hook into CBR's own AJAX actions to purge after they run ──
        add_action('wp_ajax_set_widget_country', [$this, 'on_cbr_country_set'], 999);
        add_action('wp_ajax_nopriv_set_widget_country', [$this, 'on_cbr_country_set'], 999);
        add_action('wp_ajax_set_cart_page_country', [$this, 'on_cbr_country_set'], 999);
        add_action('wp_ajax_nopriv_set_cart_page_country', [$this, 'on_cbr_country_set'], 999);

        // ── Frontend JS ──
        add_action('wp_enqueue_scripts', [$this, 'enqueue_scripts']);

        // ── Admin settings ──
        add_filter('woocommerce_get_settings_advanced', [$this, 'add_settings'], 10, 2);
        add_filter('woocommerce_get_sections_advanced', [$this, 'add_section']);

        // ── HPOS compatibility ──
        add_action('before_woocommerce_init', [$this, 'declare_hpos_compatibility']);
    }

    // =====================================================================
    //  LITESPEED CACHE VARY — The core fix
    // =====================================================================

    /**
     * Tell LiteSpeed to cache separate page versions per "country" cookie value.
     *
     * Without this, LiteSpeed caches one version and serves it to everyone,
     * so CBR's product restrictions appear frozen on the first country that
     * loaded the page.
     *
     * Used by both litespeed_vary_cookies (global registration) and
     * litespeed_vary_curr_cookies (current response).
     */
    public function add_vary_cookie($cookies) {
        if (!is_array($cookies)) {
            $cookies = [];
        }
        if (!in_array(self::CBR_COOKIE, $cookies, true)) {
            $cookies[] = self::CBR_COOKIE;
        }
        return $cookies;
    }

    // =====================================================================
    //  COUNTRY COOKIE — Ensure it exists on first visit
    // =====================================================================

    /**
     * If the CBR "country" cookie is not set yet (first visit), set it
     * based on WooCommerce geolocation so that LiteSpeed immediately
     * has a vary value to work with.
     */
    public function ensure_country_cookie() {
        if (is_admin() || wp_doing_cron()) {
            return;
        }

        // If CBR already set the cookie, don't interfere
        if (!empty($_COOKIE[self::CBR_COOKIE])) {
            return;
        }

        $country = $this->detect_country();
        if ($country) {
            $this->set_cookie($country);
        }
    }

    /**
     * Detect country from WooCommerce data / geolocation.
     */
    private function detect_country() {
        if (function_exists('WC') && WC()->customer) {
            $country = WC()->customer->get_shipping_country();
            if ($country) return $country;

            $country = WC()->customer->get_billing_country();
            if ($country) return $country;
        }

        if (class_exists('WC_Geolocation')) {
            $location = WC_Geolocation::geolocate_ip();
            if (!empty($location['country'])) {
                return $location['country'];
            }
        }

        $default = get_option('woocommerce_default_country', '');
        if ($default) {
            $parts = explode(':', $default);
            return $parts[0];
        }

        return '';
    }

    /**
     * Set the CBR-compatible "country" cookie.
     */
    private function set_cookie($country) {
        $country = sanitize_text_field($country);
        setcookie(self::CBR_COOKIE, $country, [
            'expires'  => time() + DAY_IN_SECONDS,
            'path'     => COOKIEPATH ?: '/',
            'domain'   => COOKIE_DOMAIN ?: '',
            'secure'   => is_ssl(),
            'httponly'  => false,
            'samesite' => 'Lax',
        ]);
        $_COOKIE[self::CBR_COOKIE] = $country;
    }

    // =====================================================================
    //  CACHE PURGE
    // =====================================================================

    /**
     * Purge LiteSpeed cache. Called whenever we detect a country change.
     */
    private function purge_cache() {
        $mode = get_option('wc_lscc_purge_mode', 'smart');

        if ($mode === 'all') {
            do_action('litespeed_purge_all');
            return;
        }

        // Smart purge: product-related content only
        do_action('litespeed_purge_posttype', 'product');

        $shop_id = wc_get_page_id('shop');
        if ($shop_id > 0) {
            do_action('litespeed_purge_post', $shop_id);
        }

        // Purge by common cache tags
        $tags = ['product_cat', 'frontpage', 'home'];
        foreach ($tags as $tag) {
            do_action('litespeed_purge', $tag);
        }
    }

    // =====================================================================
    //  AJAX ENDPOINT — Called by our JS after CBR changes country
    // =====================================================================

    /**
     * Purge LiteSpeed cache after a country change.
     * CBR handles the cookie and WC session itself — we just purge.
     */
    public function ajax_purge() {
        check_ajax_referer('wc_lscc_nonce', 'nonce');

        // Tell LiteSpeed this AJAX response itself is not cacheable
        do_action('litespeed_control_set_nocache', 'wc-lscc: country change purge');

        $new_country = isset($_POST['country']) ? sanitize_text_field($_POST['country']) : '';

        $this->purge_cache();

        wp_send_json_success([
            'country' => $new_country,
            'purged'  => true,
        ]);
    }

    // =====================================================================
    //  HOOK INTO CBR's OWN AJAX — Purge after CBR processes country change
    // =====================================================================

    /**
     * CBR uses AJAX actions "set_widget_country" and "set_cart_page_country"
     * to update the country. We hook in at low priority (999) to purge cache
     * after CBR finishes its work.
     *
     * CBR calls wp_send_json() which exits, so this only runs if CBR hasn't
     * exited yet. As a safety net — the JS-side purge is the primary method.
     */
    public function on_cbr_country_set() {
        $this->purge_cache();
    }

    // =====================================================================
    //  SERVER-SIDE HOOKS — WooCommerce native country changes
    // =====================================================================

    /**
     * Checkout order review update (user changed country dropdown).
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

        $current = isset($_COOKIE[self::CBR_COOKIE]) ? sanitize_text_field($_COOKIE[self::CBR_COOKIE]) : '';

        if ($current !== $new_country) {
            $this->set_cookie($new_country);
            $this->purge_cache();
        }
    }

    /**
     * Customer saves address in My Account.
     */
    public function on_address_save($user_id, $address_type) {
        $customer = new WC_Customer($user_id);
        $country  = ($address_type === 'shipping')
            ? $customer->get_shipping_country()
            : $customer->get_billing_country();

        if (!$country) {
            return;
        }

        $current = isset($_COOKIE[self::CBR_COOKIE]) ? sanitize_text_field($_COOKIE[self::CBR_COOKIE]) : '';

        if ($current !== $country) {
            $this->set_cookie($country);
            $this->purge_cache();
        }
    }

    // =====================================================================
    //  FRONTEND JAVASCRIPT
    // =====================================================================

    public function enqueue_scripts() {
        if (is_admin()) {
            return;
        }

        wp_enqueue_script('jquery');

        wp_localize_script('jquery', 'wc_lscc', [
            'ajax_url' => admin_url('admin-ajax.php'),
            'nonce'    => wp_create_nonce('wc_lscc_nonce'),
        ]);

        add_action('wp_footer', [$this, 'inline_script'], 99);
    }

    /**
     * Inline JS that intercepts CBR's country-change functions and
     * purges LiteSpeed cache + reloads the page.
     *
     * CBR uses two global JS functions to change country:
     *   - setCountryCookie(name, value, days)  → sets cookie + reloads
     *   - setCookie(name, value, days)          → sets cookie, no reload
     *
     * CBR also listens for changes on #calc_shipping_country and
     * #shipping_country. We wrap CBR's functions so that after they
     * run, we fire a cache purge and force a reload.
     */
    public function inline_script() {
        ?>
        <script type="text/javascript">
        (function($) {
            if (typeof wc_lscc === 'undefined') return;

            var purging = false;

            /**
             * Fire cache purge AJAX and reload with cache-bust param.
             */
            function purgeAndReload(countryCode) {
                if (purging || !countryCode || countryCode.length !== 2) return;
                purging = true;

                $.ajax({
                    url: wc_lscc.ajax_url,
                    type: 'POST',
                    data: {
                        action: 'wc_lscc_purge',
                        nonce: wc_lscc.nonce,
                        country: countryCode
                    },
                    complete: function() {
                        // Reload with cache-bust param to bypass any edge cache
                        var url = new URL(window.location.href);
                        url.searchParams.set('lscc', Date.now());
                        window.location.href = url.toString();
                    }
                });
            }

            /**
             * Wrap CBR's setCountryCookie — called by the admin bar dropdown
             * and the widget popup. Original: sets cookie then reloads.
             * We intercept to purge LiteSpeed before the reload happens.
             */
            if (typeof window.setCountryCookie === 'function') {
                var _origSetCountryCookie = window.setCountryCookie;
                window.setCountryCookie = function(cookieName, cookieValue, nDays) {
                    // Let CBR set the cookie
                    document.cookie = cookieName + '=' + cookieValue +
                        ';path=/;max-age=' + (nDays * 86400) + ';SameSite=Lax';

                    // Purge LS cache and reload (replaces CBR's own reload)
                    purgeAndReload(cookieValue);
                };
            }

            /**
             * Wrap CBR's setCookie — called by the widget/shortcode dropdown
             * and checkout country selectors. Original: sets cookie, no reload.
             * We add a purge + reload.
             */
            if (typeof window.setCookie === 'function') {
                var _origSetCookie = window.setCookie;
                window.setCookie = function(cookieName, cookieValue, nDays) {
                    // Let CBR set the cookie
                    document.cookie = cookieName + '=' + cookieValue +
                        ';path=/;max-age=' + (nDays * 86400) + ';SameSite=Lax';

                    // Purge LS cache and reload
                    purgeAndReload(cookieValue);
                };
            }

            // ── Also listen to the selectors CBR binds to ──

            // CBR admin bar dropdown
            $(document.body).on('change', '.display-country-for-customer .country', function() {
                purgeAndReload($(this).val());
            });

            // CBR sidebar widget dropdown
            $(document.body).on('change', '.widget-country', function() {
                purgeAndReload($(this).val());
            });

            // CBR shortcode dropdown
            $(document.body).on('change', '.select-country-dropdown', function() {
                purgeAndReload($(this).val());
            });

            // WooCommerce shipping calculator + checkout country selects
            // (CBR also hooks into these: #calc_shipping_country, #shipping_country)
            $(document.body).on('change', '#calc_shipping_country, #shipping_country, #billing_country', function() {
                var val = $(this).val();
                if (val && val.length === 2) {
                    purgeAndReload(val);
                }
            });

            // ── Clean up cache-bust parameter after page loads ──
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
    //  ADMIN SETTINGS
    // =====================================================================

    public function add_section($sections) {
        $sections['litespeed-country'] = __('LiteSpeed Country Cache', 'wc-litespeed-country-cache');
        return $sections;
    }

    public function add_settings($settings, $current_section) {
        if ('litespeed-country' !== $current_section) {
            return $settings;
        }

        return [
            [
                'title' => __('LiteSpeed Country Cache Settings', 'wc-litespeed-country-cache'),
                'type'  => 'title',
                'desc'  => __(
                    'Fixes LiteSpeed Cache serving stale pages when users change country in Country Based Restrictions PRO. ' .
                    'The plugin tells LiteSpeed to cache separate page versions per country and purges cache on country change.',
                    'wc-litespeed-country-cache'
                ),
                'id'    => 'wc_lscc_settings',
            ],
            [
                'title'   => __('Purge Mode', 'wc-litespeed-country-cache'),
                'desc'    => __(
                    'Smart: purges product pages and shop archive only. Full: purges the entire LiteSpeed cache.',
                    'wc-litespeed-country-cache'
                ),
                'id'      => 'wc_lscc_purge_mode',
                'default' => 'smart',
                'type'    => 'select',
                'options' => [
                    'smart' => __('Smart (product & shop pages)', 'wc-litespeed-country-cache'),
                    'all'   => __('Full (entire cache)', 'wc-litespeed-country-cache'),
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
