<?php
/**
 * Plugin Name: WooCommerce Loyalty Coupon
 * Description: Automatically issue $35 coupons for next purchase when customers spend over $250
 * Version: 1.0.5
 * Author: Your Name
 * License: GPL v2 or later
 */

if ( ! defined( 'ABSPATH' ) ) {
	exit;
}

// Activation
register_activation_hook( __FILE__, 'wc_loyalty_activate' );

function wc_loyalty_activate() {
	add_option( 'wc_loyalty_coupon_amount', 35 );
	add_option( 'wc_loyalty_coupon_min_amount', 250 );
	add_option( 'wc_loyalty_coupon_days_valid', 30 );
}

// Initialize plugin
add_action( 'plugins_loaded', 'wc_loyalty_init', 20 );

function wc_loyalty_init() {
	if ( ! function_exists( 'WC' ) ) {
		return;
	}

	if ( is_admin() ) {
		add_action( 'admin_menu', 'wc_loyalty_admin_menu' );
		add_action( 'admin_init', 'wc_loyalty_admin_init' );
		return;
	}

	add_action( 'woocommerce_before_checkout_form', 'wc_loyalty_checkout_form', 5 );
	add_action( 'woocommerce_checkout_process', 'wc_loyalty_validate_checkout' );
	add_action( 'woocommerce_checkout_update_order_meta', 'wc_loyalty_save_meta' );
	add_action( 'woocommerce_order_status_completed', 'wc_loyalty_create_coupon' );
}

// Checkout form
function wc_loyalty_checkout_form() {
	if ( ! WC()->cart ) {
		return;
	}

	$total = floatval( WC()->cart->get_total( false ) );
	$min = floatval( get_option( 'wc_loyalty_coupon_min_amount', 250 ) );

	if ( $total < $min ) {
		return;
	}

	$amount = floatval( get_option( 'wc_loyalty_coupon_amount', 35 ) );
	$choice = isset( $_POST['wc_loyalty_choice'] ) ? sanitize_text_field( $_POST['wc_loyalty_choice'] ) : 'keep';
	$email = isset( $_POST['wc_loyalty_email'] ) ? sanitize_email( $_POST['wc_loyalty_email'] ) : '';

	echo '<div style="background:#f5f5f5;padding:20px;margin:20px 0;border-left:4px solid #0073aa;border-radius:4px;">';
	echo '<h3>You\'ve Earned a $' . number_format( $amount, 2 ) . ' Loyalty Coupon!</h3>';
	echo '<p>What would you like to do with it?</p>';
	echo '<label style="display:block;margin:10px 0;"><input type="radio" name="wc_loyalty_choice" value="keep" ' . checked( $choice, 'keep', false ) . ' onchange="toggleEmail()" /> Keep it for my next purchase</label>';
	echo '<label style="display:block;margin:10px 0;"><input type="radio" name="wc_loyalty_choice" value="gift" ' . checked( $choice, 'gift', false ) . ' onchange="toggleEmail()" /> Send it to a friend</label>';
	echo '<div id="friend_email_div" style="display:' . ( $choice === 'gift' ? 'block' : 'none' ) . ';margin:15px 0;">';
	echo '<label>Friend\'s Email:</label>';
	echo '<input type="email" name="wc_loyalty_email" placeholder="friend@example.com" value="' . esc_attr( $email ) . '" style="width:100%;padding:8px;box-sizing:border-box;" />';
	echo '</div>';
	echo '<script>function toggleEmail(){var e=document.querySelector(\'input[name="wc_loyalty_choice"]:checked\');document.getElementById("friend_email_div").style.display=e&&"gift"===e.value?"block":"none";}</script>';
	echo '</div>';
}

// Validate checkout
function wc_loyalty_validate_checkout() {
	if ( ! WC()->cart ) {
		return;
	}

	$total = floatval( WC()->cart->get_total( false ) );
	$min = floatval( get_option( 'wc_loyalty_coupon_min_amount', 250 ) );

	if ( $total < $min ) {
		return;
	}

	$choice = isset( $_POST['wc_loyalty_choice'] ) ? sanitize_text_field( $_POST['wc_loyalty_choice'] ) : 'keep';

	if ( 'gift' === $choice ) {
		$email = isset( $_POST['wc_loyalty_email'] ) ? sanitize_email( $_POST['wc_loyalty_email'] ) : '';
		if ( ! $email || ! is_email( $email ) ) {
			wc_add_notice( 'Please enter a valid email for your friend.', 'error' );
		}
	}
}

// Save order metadata
function wc_loyalty_save_meta( $order_id ) {
	if ( ! WC()->cart ) {
		return;
	}

	$total = floatval( WC()->cart->get_total( false ) );
	$min = floatval( get_option( 'wc_loyalty_coupon_min_amount', 250 ) );

	if ( $total < $min ) {
		return;
	}

	$choice = isset( $_POST['wc_loyalty_choice'] ) ? sanitize_text_field( $_POST['wc_loyalty_choice'] ) : 'keep';
	update_post_meta( $order_id, '_wc_loyalty_choice', $choice );

	if ( 'gift' === $choice ) {
		$email = isset( $_POST['wc_loyalty_email'] ) ? sanitize_email( $_POST['wc_loyalty_email'] ) : '';
		update_post_meta( $order_id, '_wc_loyalty_friend_email', $email );
	}
}

// Create coupon on order completion
function wc_loyalty_create_coupon( $order_id ) {
	if ( get_post_meta( $order_id, '_wc_loyalty_processed', true ) ) {
		return;
	}

	$order = wc_get_order( $order_id );
	if ( ! $order ) {
		return;
	}

	$total = floatval( $order->get_total() );
	$min = floatval( get_option( 'wc_loyalty_coupon_min_amount', 250 ) );

	if ( $total < $min ) {
		return;
	}

	$amount = floatval( get_option( 'wc_loyalty_coupon_amount', 35 ) );
	$days = intval( get_option( 'wc_loyalty_coupon_days_valid', 30 ) );
	$code = 'LOYALTY-' . $order_id . '-' . strtoupper( substr( md5( time() ), 0, 6 ) );

	$coupon = new WC_Coupon();
	$coupon->set_code( $code );
	$coupon->set_discount_type( 'fixed_cart' );
	$coupon->set_amount( $amount );
	$coupon->set_usage_limit( 1 );
	$coupon->set_usage_limit_per_user( 1 );
	$coupon->set_individual_use( true );

	$choice = get_post_meta( $order_id, '_wc_loyalty_choice', true );
	if ( 'gift' === $choice ) {
		$recipient = get_post_meta( $order_id, '_wc_loyalty_friend_email', true );
	} else {
		$recipient = $order->get_billing_email();
	}

	if ( ! $recipient ) {
		return;
	}

	$coupon->set_email_restrictions( array( $recipient ) );
	$coupon->set_date_expires( strtotime( "+$days days" ) );

	if ( $coupon->save() ) {
		update_post_meta( $order_id, '_wc_loyalty_processed', '1' );
		update_post_meta( $coupon->get_id(), '_wc_loyalty_order_id', $order_id );

		$subject = 'Your $' . number_format( $amount, 2 ) . ' Coupon';
		$message = "You've received a coupon!\n\nCode: $code\nExpires: " . date( 'Y-m-d', strtotime( "+$days days" ) ) . "\n\nUse it at checkout!";

		wp_mail( $recipient, $subject, $message );
	}
}

// Admin menu
function wc_loyalty_admin_menu() {
	if ( ! current_user_can( 'manage_woocommerce' ) ) {
		return;
	}

	add_submenu_page(
		'woocommerce',
		'Loyalty Coupons',
		'Loyalty Coupons',
		'manage_woocommerce',
		'wc-loyalty-coupon',
		'wc_loyalty_admin_page'
	);
}

// Admin init
function wc_loyalty_admin_init() {
	register_setting( 'wc_loyalty_coupon_group', 'wc_loyalty_coupon_amount', array( 'sanitize_callback' => 'floatval' ) );
	register_setting( 'wc_loyalty_coupon_group', 'wc_loyalty_coupon_min_amount', array( 'sanitize_callback' => 'floatval' ) );
	register_setting( 'wc_loyalty_coupon_group', 'wc_loyalty_coupon_days_valid', array( 'sanitize_callback' => 'intval' ) );
}

// Admin page
function wc_loyalty_admin_page() {
	if ( ! current_user_can( 'manage_woocommerce' ) ) {
		wp_die( 'Unauthorized' );
	}
	?>
	<div class="wrap">
		<h1>Loyalty Coupons Settings</h1>
		<form method="post" action="options.php">
			<?php settings_fields( 'wc_loyalty_coupon_group' ); ?>
			<table class="form-table">
				<tr>
					<th><label for="wc_loyalty_coupon_amount">Coupon Amount ($)</label></th>
					<td><input type="number" step="0.01" id="wc_loyalty_coupon_amount" name="wc_loyalty_coupon_amount" value="<?php echo esc_attr( get_option( 'wc_loyalty_coupon_amount', 35 ) ); ?>" /></td>
				</tr>
				<tr>
					<th><label for="wc_loyalty_coupon_min_amount">Minimum Order Amount ($)</label></th>
					<td><input type="number" step="0.01" id="wc_loyalty_coupon_min_amount" name="wc_loyalty_coupon_min_amount" value="<?php echo esc_attr( get_option( 'wc_loyalty_coupon_min_amount', 250 ) ); ?>" /></td>
				</tr>
				<tr>
					<th><label for="wc_loyalty_coupon_days_valid">Coupon Valid (Days)</label></th>
					<td><input type="number" id="wc_loyalty_coupon_days_valid" name="wc_loyalty_coupon_days_valid" value="<?php echo esc_attr( get_option( 'wc_loyalty_coupon_days_valid', 30 ) ); ?>" min="1" /></td>
				</tr>
			</table>
			<?php submit_button(); ?>
		</form>
	</div>
	<?php
}
