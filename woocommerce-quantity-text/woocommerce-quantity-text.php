<?php
/**
 * Plugin Name: WooCommerce Quantity Text
 * Plugin URI: https://github.com/renthemighty/Plugins
 * Description: Adds custom text above the quantity selector on product pages, configurable per product category (e.g. "Pack of 10", "Sold by the pound").
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

        // Frontend
        add_action( 'woocommerce_before_quantity_input_field', [ $this, 'display_quantity_text' ] );
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
     * Display text above the quantity input field.
     *
     * Hooks into woocommerce_before_quantity_input_field which fires
     * immediately before the <input type="number"> inside the quantity wrapper.
     */
    public function display_quantity_text() {
        // Only run on single product pages where global $product is reliable.
        // On the cart page this hook also fires, but global $product is stale
        // and get_the_ID() returns the cart page ID — not a product.
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

        $mappings = $this->get_mappings();
        if ( empty( $mappings ) ) {
            return;
        }

        // Get the product's category term IDs
        $product_cat_ids = $product->get_category_ids();
        if ( empty( $product_cat_ids ) ) {
            return;
        }

        // Find the first matching mapping (most specific wins – order of saved rules)
        $text = '';
        foreach ( $mappings as $term_id => $label ) {
            if ( in_array( (int) $term_id, $product_cat_ids, true ) ) {
                $text = $label;
                break;
            }
        }

        if ( $text === '' ) {
            return;
        }

        printf(
            '<span class="wc-quantity-text">%s</span>',
            esc_html( $text )
        );
    }
}

// Initialise after WooCommerce is loaded.
add_action( 'plugins_loaded', function () {
    if ( class_exists( 'WooCommerce' ) ) {
        WC_Quantity_Text::instance();
    }
} );
