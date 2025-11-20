<?php
/**
 * Plugin Name: WooCommerce Loyalty Coupon
 * Description: Automatically issue $35 coupons for next purchase when customers spend over $250
 * Version: 1.0.0
 * Author: Your Name
 * License: GPL v2 or later
 * Text Domain: wc-loyalty-coupon
 * Domain Path: /languages
 * Requires at least: 5.0
 * Requires PHP: 7.4
 * Requires Plugins: woocommerce
 * WC requires at least: 3.0
 * WC tested up to: 8.5
 */

if ( ! defined( 'ABSPATH' ) ) {
	exit;
}

define( 'WC_LOYALTY_COUPON_VERSION', '1.0.0' );
define( 'WC_LOYALTY_COUPON_PATH', plugin_dir_path( __FILE__ ) );
define( 'WC_LOYALTY_COUPON_URL', plugin_dir_url( __FILE__ ) );

/**
 * Initialize plugin
 */
function wc_loyalty_coupon_init() {
	// Only proceed if WooCommerce is active
	if ( ! class_exists( 'WooCommerce' ) ) {
		return;
	}

	// Include required files
	require_once WC_LOYALTY_COUPON_PATH . 'includes/class-wc-loyalty-coupon-manager.php';
	require_once WC_LOYALTY_COUPON_PATH . 'includes/class-wc-loyalty-coupon-admin.php';

	// Initialize classes
	WC_Loyalty_Coupon_Manager::init();

	if ( is_admin() ) {
		WC_Loyalty_Coupon_Admin::init();
	}
}
add_action( 'plugins_loaded', 'wc_loyalty_coupon_init' );

/**
 * Register activation hook
 */
register_activation_hook( __FILE__, 'wc_loyalty_coupon_activate' );
function wc_loyalty_coupon_activate() {
	if ( ! class_exists( 'WooCommerce' ) ) {
		wp_die( 'This plugin requires WooCommerce to be activated.' );
	}

	// Set default options if not exist
	if ( ! get_option( 'wc_loyalty_coupon_amount' ) ) {
		add_option( 'wc_loyalty_coupon_amount', 35 );
	}
	if ( ! get_option( 'wc_loyalty_coupon_min_amount' ) ) {
		add_option( 'wc_loyalty_coupon_min_amount', 250 );
	}
	if ( ! get_option( 'wc_loyalty_coupon_days_valid' ) ) {
		add_option( 'wc_loyalty_coupon_days_valid', 30 );
	}
}

/**
 * Register deactivation hook
 */
register_deactivation_hook( __FILE__, 'wc_loyalty_coupon_deactivate' );
function wc_loyalty_coupon_deactivate() {
	// Cleanup if needed
}
