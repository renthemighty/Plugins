<?php
/**
 * Plugin Name: WooCommerce Quantity Text
 * Plugin URI: https://github.com/renthemighty/Plugins
 * Description: Adds custom text above the quantity selector on product pages, configurable per product category (e.g. "Pack of 10", "Sold by the pound").
 * Version: 1.4.0
 * Author: Megatron
 * Author URI: https://github.com/renthemighty
 * Requires at least: 5.0
 * Tested up to: 6.4
 * Requires PHP: 7.2
 * WC requires at least: 5.0
 * WC tested up to: 8.5
 * License: GPL v2 or later
 * License URI: https://www.gnu.org/licenses/gpl-2.0.html
 * Text Domain: woocommerce-quantity-text
 */

defined( 'ABSPATH' ) || exit;

class WC_Quantity_Text {

    private static $instance = null;

    /**
     * Option key for storing all category-text mappings.
     * Stored as a single autoloaded option for optimal performance.
     * Format: [ term_id => 'display text', ... ]
     */
    const OPTION_KEY = 'wc_quantity_text_mappings';

    /**
     * Cached mappings loaded once per request.
     */
    private $mappings = null;

    public static function instance() {
        if ( null === self::$instance ) {
            self::$instance = new self();
        }
        return self::$instance;
    }

    private function __construct() {
        // Admin
        add_action( 'admin_menu', [ $this, 'add_admin_menu' ] );
        add_action( 'wp_ajax_wc_quantity_text_save', [ $this, 'ajax_save_mappings' ] );

        // Frontend — JavaScript-based replacement that works on ALL themes.
        //
        // Many themes (Flatsome, Woodmart, Elementor, etc.) override the
        // WooCommerce quantity templates and strip the PHP action hooks.
        // Instead of injecting new HTML, we replace the existing "Quantity"
        // label text that every theme already renders. This is done via a
        // small inline script on product pages — guaranteed to work
        // regardless of which templates or page builders are in use.
        add_action( 'wp_footer', [ $this, 'frontend_script' ] );
    }

    // =========================================================================
    // Database helpers
    // =========================================================================

    /**
     * Get all mappings. Loaded once per request from a single autoloaded option.
     */
    private function get_mappings() {
        if ( null === $this->mappings ) {
            $this->mappings = get_option( self::OPTION_KEY, [] );
            if ( ! is_array( $this->mappings ) ) {
                $this->mappings = [];
            }
        }
        return $this->mappings;
    }

    /**
     * Save mappings array to a single option row.
     */
    private function save_mappings( $mappings ) {
        $this->mappings = $mappings;
        return update_option( self::OPTION_KEY, $mappings, true ); // autoload = true
    }

    /**
     * Resolve the quantity text for a given product. Returns empty string if none.
     */
    private function get_text_for_product( $product ) {
        if ( ! $product instanceof WC_Product ) {
            return '';
        }

        $mappings = $this->get_mappings();
        if ( empty( $mappings ) ) {
            return '';
        }

        $product_cat_ids = $product->get_category_ids();
        if ( empty( $product_cat_ids ) ) {
            return '';
        }

        foreach ( $mappings as $term_id => $label ) {
            if ( in_array( (int) $term_id, $product_cat_ids, true ) ) {
                return $label;
            }
        }

        return '';
    }

    // =========================================================================
    // Admin menu & page
    // =========================================================================

    public function add_admin_menu() {
        add_submenu_page(
            'woocommerce',
            __( 'Quantity Text', 'woocommerce-quantity-text' ),
            __( 'Quantity Text', 'woocommerce-quantity-text' ),
            'manage_woocommerce',
            'wc-quantity-text',
            [ $this, 'render_admin_page' ]
        );
    }

    public function sanitize_mappings( $input ) {
        $clean = [];
        if ( is_array( $input ) ) {
            foreach ( $input as $term_id => $text ) {
                $term_id = absint( $term_id );
                $text    = sanitize_text_field( $text );
                if ( $term_id && $text !== '' ) {
                    $clean[ $term_id ] = $text;
                }
            }
        }
        return $clean;
    }

    public function ajax_save_mappings() {
        check_ajax_referer( 'wc_quantity_text_save', 'nonce' );

        if ( ! current_user_can( 'manage_woocommerce' ) ) {
            wp_send_json_error( 'Unauthorized' );
        }

        $raw      = isset( $_POST['mappings'] ) ? wp_unslash( $_POST['mappings'] ) : '{}';
        $decoded  = json_decode( $raw, true );
        $mappings = $this->sanitize_mappings( is_array( $decoded ) ? $decoded : [] );

        $this->save_mappings( $mappings );
        wp_send_json_success();
    }

    public function render_admin_page() {
        $mappings   = $this->get_mappings();
        $categories = get_terms( [
            'taxonomy'   => 'product_cat',
            'hide_empty' => false,
            'orderby'    => 'name',
        ] );

        if ( is_wp_error( $categories ) ) {
            $categories = [];
        }

        ?>
        <style>
            .wcqt-wrap { max-width: 800px; }
            .wcqt-row { display: flex; gap: 12px; align-items: center; margin-bottom: 10px; }
            .wcqt-row select { min-width: 250px; }
            .wcqt-row input[type="text"] { flex: 1; min-width: 200px; }
            .wcqt-row .button-link-delete { color: #b32d2e; cursor: pointer; text-decoration: none; padding: 4px 8px; font-size: 18px; line-height: 1; }
            .wcqt-row .button-link-delete:hover { color: #a00; }
            .wcqt-notice { display: none; padding: 10px 14px; margin: 10px 0; border-left: 4px solid #00a32a; background: #fff; }
            .wcqt-notice.wcqt-error { border-left-color: #d63638; }
            .wcqt-actions { margin-top: 16px; display: flex; gap: 10px; align-items: center; }
        </style>

        <div class="wrap wcqt-wrap">
            <h1><?php esc_html_e( 'Quantity Text per Category', 'woocommerce-quantity-text' ); ?></h1>
            <p><?php esc_html_e( 'Assign text that appears above the quantity selector for products in each category.', 'woocommerce-quantity-text' ); ?></p>

            <div id="wcqt-notice" class="wcqt-notice"></div>

            <div id="wcqt-mappings">
                <?php if ( ! empty( $mappings ) ) : ?>
                    <?php foreach ( $mappings as $term_id => $text ) : ?>
                        <div class="wcqt-row">
                            <select>
                                <option value=""><?php esc_html_e( '— Select category —', 'woocommerce-quantity-text' ); ?></option>
                                <?php foreach ( $categories as $cat ) : ?>
                                    <option value="<?php echo esc_attr( $cat->term_id ); ?>" <?php selected( $cat->term_id, $term_id ); ?>>
                                        <?php echo esc_html( $cat->name ); ?>
                                    </option>
                                <?php endforeach; ?>
                            </select>
                            <input type="text" value="<?php echo esc_attr( $text ); ?>" placeholder="<?php esc_attr_e( 'e.g. Pack of 10', 'woocommerce-quantity-text' ); ?>" />
                            <a href="#" class="wcqt-remove button-link-delete">&times;</a>
                        </div>
                    <?php endforeach; ?>
                <?php endif; ?>
            </div>

            <template id="wcqt-row-template">
                <div class="wcqt-row">
                    <select>
                        <option value=""><?php esc_html_e( '— Select category —', 'woocommerce-quantity-text' ); ?></option>
                        <?php foreach ( $categories as $cat ) : ?>
                            <option value="<?php echo esc_attr( $cat->term_id ); ?>">
                                <?php echo esc_html( $cat->name ); ?>
                            </option>
                        <?php endforeach; ?>
                    </select>
                    <input type="text" value="" placeholder="<?php esc_attr_e( 'e.g. Pack of 10', 'woocommerce-quantity-text' ); ?>" />
                    <a href="#" class="wcqt-remove button-link-delete">&times;</a>
                </div>
            </template>

            <div class="wcqt-actions">
                <a href="#" id="wcqt-add-row" class="button button-secondary"><?php esc_html_e( '+ Add Rule', 'woocommerce-quantity-text' ); ?></a>
                <input type="submit" id="wcqt-save" class="button button-primary" value="<?php esc_attr_e( 'Save Changes', 'woocommerce-quantity-text' ); ?>" />
            </div>
        </div>

        <script>
        (function() {
            var ajaxUrl = <?php echo wp_json_encode( admin_url( 'admin-ajax.php' ) ); ?>;
            var nonce   = <?php echo wp_json_encode( wp_create_nonce( 'wc_quantity_text_save' ) ); ?>;

            var wrap = document.getElementById('wcqt-mappings');
            var tmpl = document.getElementById('wcqt-row-template');
            if (!wrap || !tmpl) return;

            document.getElementById('wcqt-add-row').addEventListener('click', function(e) {
                e.preventDefault();
                var clone = tmpl.content.cloneNode(true);
                wrap.appendChild(clone);
                bindRemoveButtons();
            });

            function bindRemoveButtons() {
                wrap.querySelectorAll('.wcqt-remove').forEach(function(btn) {
                    btn.onclick = function(e) {
                        e.preventDefault();
                        this.closest('.wcqt-row').remove();
                    };
                });
            }
            bindRemoveButtons();

            document.getElementById('wcqt-save').addEventListener('click', function(e) {
                e.preventDefault();
                var rows = wrap.querySelectorAll('.wcqt-row');
                var mappings = {};
                rows.forEach(function(row) {
                    var sel = row.querySelector('select');
                    var inp = row.querySelector('input[type="text"]');
                    if (sel && inp && sel.value && inp.value.trim()) {
                        mappings[sel.value] = inp.value.trim();
                    }
                });

                var btn = document.getElementById('wcqt-save');
                btn.disabled = true;
                btn.value = 'Saving\u2026';

                var xhr = new XMLHttpRequest();
                xhr.open('POST', ajaxUrl);
                xhr.setRequestHeader('Content-Type', 'application/x-www-form-urlencoded');
                xhr.onload = function() {
                    btn.disabled = false;
                    btn.value = <?php echo wp_json_encode( __( 'Save Changes', 'woocommerce-quantity-text' ) ); ?>;
                    var notice = document.getElementById('wcqt-notice');
                    try {
                        var res = JSON.parse(xhr.responseText);
                        if (xhr.status === 200 && res.success) {
                            notice.textContent = <?php echo wp_json_encode( __( 'Settings saved.', 'woocommerce-quantity-text' ) ); ?>;
                            notice.className = 'wcqt-notice';
                        } else {
                            notice.textContent = <?php echo wp_json_encode( __( 'Error saving settings.', 'woocommerce-quantity-text' ) ); ?>;
                            notice.className = 'wcqt-notice wcqt-error';
                        }
                    } catch (err) {
                        notice.textContent = <?php echo wp_json_encode( __( 'Error saving settings.', 'woocommerce-quantity-text' ) ); ?>;
                        notice.className = 'wcqt-notice wcqt-error';
                    }
                    notice.style.display = 'block';
                };
                xhr.onerror = function() {
                    btn.disabled = false;
                    btn.value = <?php echo wp_json_encode( __( 'Save Changes', 'woocommerce-quantity-text' ) ); ?>;
                    var notice = document.getElementById('wcqt-notice');
                    notice.textContent = <?php echo wp_json_encode( __( 'Network error. Please try again.', 'woocommerce-quantity-text' ) ); ?>;
                    notice.className = 'wcqt-notice wcqt-error';
                    notice.style.display = 'block';
                };
                xhr.send('action=wc_quantity_text_save&nonce=' + encodeURIComponent(nonce) + '&mappings=' + encodeURIComponent(JSON.stringify(mappings)));
            });
        })();
        </script>
        <?php
    }

    // =========================================================================
    // Frontend
    // =========================================================================

    /**
     * Output inline CSS + JS on single product pages.
     *
     * Anchors on input[name="quantity"] which exists on every WooCommerce
     * theme regardless of template overrides, then works outward to find
     * and replace the "Quantity" label. Covers:
     *  - Labels inside .quantity (Storefront, Astra, OceanWP)
     *  - Labels with screen-reader-text (core WooCommerce default)
     *  - Flatsome's custom quantity wrapper and visible labels
     *  - Elementor Pro add-to-cart widget
     *  - Woodmart's custom quantity template
     *  - Any other theme: broad text-node scan as final fallback
     */
    public function frontend_script() {
        if ( ! is_product() ) {
            return;
        }

        global $product;

        if ( ! $product instanceof WC_Product ) {
            $product = wc_get_product( get_the_ID() );
        }

        if ( ! $product ) {
            return;
        }

        $text = $this->get_text_for_product( $product );
        if ( $text === '' ) {
            return;
        }

        ?>
        <style>
        .wc-quantity-text {
            display: block !important;
            position: static !important;
            width: auto !important;
            height: auto !important;
            overflow: visible !important;
            clip: auto !important;
            clip-path: none !important;
            margin-bottom: 6px !important;
            font-weight: 600;
            font-size: .95em;
        }
        </style>
        <script>
        (function() {
            var newText = <?php echo wp_json_encode( $text ); ?>;
            var DONE = 'data-wcqt-done';

            function isQuantityWord(s) {
                s = s.trim().replace(/:$/, '').trim().toLowerCase();
                return /^(quantity|qty\.?|product quantity)$/i.test(s)
                    || /quantity$/i.test(s);
            }

            function apply() {
                // Anchor: find every quantity input on the page.
                var inputs = document.querySelectorAll('input[name="quantity"]');

                for (var i = 0; i < inputs.length; i++) {
                    var input = inputs[i];

                    // Walk up to the .quantity wrapper (or direct parent).
                    var wrapper = input.closest('.quantity') || input.parentNode;
                    if (!wrapper || wrapper.getAttribute(DONE)) continue;

                    // Do NOT touch labels INSIDE .quantity — those are
                    // screen-reader-only labels that should stay hidden.
                    // Instead, look OUTSIDE the wrapper for the visible
                    // "Quantity:" text that themes render above the controls.

                    var replaced = false;

                    // --- Strategy 1: scan ancestors up to form for "Quantity" text ---
                    // Walk from the wrapper's parent up through ancestors (stopping
                    // at the form) and check each level's direct children.
                    var ancestor = wrapper.parentNode;
                    var form = input.closest('form') || document.querySelector('form.cart');
                    var ceiling = form ? form.parentNode : document.body;

                    while (ancestor && ancestor !== ceiling) {
                        var kids = ancestor.children;
                        for (var j = 0; j < kids.length; j++) {
                            var kid = kids[j];
                            // Skip the wrapper itself and any container holding it.
                            if (kid.contains(wrapper)) continue;
                            if (kid.getAttribute(DONE)) continue;
                            if (isQuantityWord(kid.textContent) && kid.children.length === 0) {
                                kid.textContent = newText;
                                kid.setAttribute(DONE, '1');
                                wrapper.setAttribute(DONE, '1');
                                replaced = true;
                                break;
                            }
                        }
                        if (replaced) break;
                        ancestor = ancestor.parentNode;
                    }
                    if (replaced) continue;

                    // --- Strategy 2: broad scan inside form ---
                    if (form) {
                        var els = form.querySelectorAll('label, th, span, p, div, h1, h2, h3, h4, h5, h6');
                        for (var k = 0; k < els.length; k++) {
                            var el = els[k];
                            // Skip anything inside .quantity (screen-reader labels).
                            if (wrapper.contains(el)) continue;
                            if (el.getAttribute(DONE)) continue;
                            if (el.children.length > 0) continue;
                            if (isQuantityWord(el.textContent)) {
                                el.textContent = newText;
                                el.setAttribute(DONE, '1');
                                wrapper.setAttribute(DONE, '1');
                                replaced = true;
                                break;
                            }
                        }
                    }
                    if (replaced) continue;

                    // --- Strategy 3: nothing found — inject above the wrapper ---
                    var span = document.createElement('span');
                    span.className = 'wc-quantity-text';
                    span.textContent = newText;
                    wrapper.parentNode.insertBefore(span, wrapper);
                    wrapper.setAttribute(DONE, '1');
                }
            }

            // Run on DOM ready.
            if (document.readyState === 'loading') {
                document.addEventListener('DOMContentLoaded', apply);
            } else {
                apply();
            }

            // Re-run on AJAX / variation switches.
            var obs = typeof MutationObserver !== 'undefined';
            if (obs) {
                var target = document.querySelector('form.cart')
                          || document.querySelector('.product');
                if (target) {
                    new MutationObserver(function() { apply(); })
                        .observe(target, { childList: true, subtree: true });
                }
            }

            // Also re-run on WooCommerce variation events (jQuery-based).
            if (typeof jQuery !== 'undefined') {
                jQuery(document).on('show_variation reset_data', 'form.variations_form', function() {
                    setTimeout(apply, 100);
                });
            }
        })();
        </script>
        <?php
    }
}

// Initialise after WooCommerce is loaded.
add_action( 'plugins_loaded', function () {
    if ( class_exists( 'WooCommerce' ) ) {
        WC_Quantity_Text::instance();
    }
} );
