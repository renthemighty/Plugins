<?php
/**
 * Plugin Name: WooCommerce Loyalty Coupon
 * Description: Automatically issue $35 coupons for next purchase when customers spend over $250
 * Version: 1.0.7
 * Author: Your Name
 * License: GPL v2 or later
 */

if ( ! defined( 'ABSPATH' ) ) {
	exit;
}

// Activation hook
register_activation_hook( __FILE__, 'wc_loyalty_activate' );

function wc_loyalty_activate() {
	add_option( 'wc_loyalty_coupon_amount', 35 );
	add_option( 'wc_loyalty_coupon_min_amount', 250 );
	add_option( 'wc_loyalty_coupon_days_valid', 30 );
	error_log( 'WC Loyalty Coupon: Plugin activated' );
}

// Initialize plugin
add_action( 'plugins_loaded', 'wc_loyalty_init', 20 );

function wc_loyalty_init() {
	error_log( 'WC Loyalty Coupon: Initializing plugin' );

	// Check if WooCommerce is active
	if ( ! function_exists( 'WC' ) || ! class_exists( 'WC_Coupon' ) ) {
		error_log( 'WC Loyalty Coupon: WooCommerce not active' );
		return;
	}

	// Admin only
	if ( is_admin() ) {
		add_action( 'admin_menu', 'wc_loyalty_admin_menu' );
		add_action( 'admin_init', 'wc_loyalty_admin_init' );
		error_log( 'WC Loyalty Coupon: Loaded in admin' );
		return;
	}

	// Frontend only
	add_action( 'woocommerce_before_checkout_form', 'wc_loyalty_checkout_form' );
	add_action( 'woocommerce_checkout_process', 'wc_loyalty_validate_checkout' );
	add_action( 'woocommerce_checkout_update_order_meta', 'wc_loyalty_save_meta' );

	// Hook into payment completion (fires immediately when payment succeeds)
	add_action( 'woocommerce_payment_complete', 'wc_loyalty_create_coupon', 10, 1 );
	// Also hook into status changes as backup
	add_action( 'woocommerce_order_status_processing', 'wc_loyalty_create_coupon', 10, 1 );
	add_action( 'woocommerce_order_status_completed', 'wc_loyalty_create_coupon', 10, 1 );

	error_log( 'WC Loyalty Coupon: Loaded on frontend' );
}

/**
 * Check if customer qualifies for coupon
 */
function wc_loyalty_qualifies() {
	try {
		$wc = WC();
		if ( ! $wc || ! $wc->cart ) {
			error_log( 'WC Loyalty Coupon: Cart not available' );
			return false;
		}

		$total = floatval( $wc->cart->get_total( false ) );
		$min = floatval( get_option( 'wc_loyalty_coupon_min_amount', 250 ) );

		$qualifies = $total >= $min;
		error_log( "WC Loyalty Coupon: Cart total: $total, Min: $min, Qualifies: " . ( $qualifies ? 'yes' : 'no' ) );

		return $qualifies;
	} catch ( Exception $e ) {
		error_log( 'WC Loyalty Coupon: Exception in qualifies: ' . $e->getMessage() );
		return false;
	}
}

/**
 * Render checkout form
 */
function wc_loyalty_checkout_form() {
	if ( ! wc_loyalty_qualifies() ) {
		return;
	}

	$amount = floatval( get_option( 'wc_loyalty_coupon_amount', 35 ) );
	$choice = isset( $_POST['wc_loyalty_choice'] ) ? sanitize_text_field( $_POST['wc_loyalty_choice'] ) : 'keep';
	$email = isset( $_POST['wc_loyalty_email'] ) ? sanitize_email( $_POST['wc_loyalty_email'] ) : '';

	error_log( "WC Loyalty Coupon: Rendering form. Choice: $choice, Email: $email" );
	?>
	<div style="background:#f5f5f5;padding:20px;margin:20px 0;border-left:4px solid #0073aa;border-radius:4px;">
		<h3>You've Earned a $<?php echo number_format( $amount, 2 ); ?> Loyalty Coupon!</h3>
		<p>What would you like to do with it?</p>

		<label style="display:block;margin:10px 0;">
			<input type="radio" name="wc_loyalty_choice" value="keep" <?php checked( $choice, 'keep' ); ?> />
			Keep it for my next purchase
		</label>

		<label style="display:block;margin:10px 0;">
			<input type="radio" name="wc_loyalty_choice" value="gift" <?php checked( $choice, 'gift' ); ?> />
			Send it to a friend
		</label>

		<div id="friend_email_div" style="display:<?php echo $choice === 'gift' ? 'block' : 'none'; ?>;margin:15px 0;">
			<label>Friend's Email:</label>
			<input type="email" name="wc_loyalty_email" placeholder="friend@example.com" value="<?php echo esc_attr( $email ); ?>" style="width:100%;padding:8px;box-sizing:border-box;" />
		</div>

		<script>
		document.addEventListener('change', function(e) {
			if ( e.target.name === 'wc_loyalty_choice' ) {
				var div = document.getElementById('friend_email_div');
				div.style.display = e.target.value === 'gift' ? 'block' : 'none';
			}
		});
		</script>
	</div>
	<?php
}

/**
 * Validate checkout
 */
function wc_loyalty_validate_checkout() {
	if ( ! wc_loyalty_qualifies() ) {
		return;
	}

	$choice = isset( $_POST['wc_loyalty_choice'] ) ? sanitize_text_field( $_POST['wc_loyalty_choice'] ) : 'keep';
	error_log( "WC Loyalty Coupon: Validating checkout. Choice: $choice" );

	if ( 'gift' === $choice ) {
		$email = isset( $_POST['wc_loyalty_email'] ) ? sanitize_email( $_POST['wc_loyalty_email'] ) : '';
		if ( ! $email || ! is_email( $email ) ) {
			error_log( "WC Loyalty Coupon: Invalid email for gift: $email" );
			wc_add_notice( 'Please enter a valid email for your friend.', 'error' );
		}
	}
}

/**
 * Save order meta
 */
function wc_loyalty_save_meta( $order_id ) {
	if ( ! wc_loyalty_qualifies() ) {
		error_log( "WC Loyalty Coupon: Order $order_id doesn't qualify (cart check)" );
		return;
	}

	$choice = isset( $_POST['wc_loyalty_choice'] ) ? sanitize_text_field( $_POST['wc_loyalty_choice'] ) : 'keep';
	update_post_meta( $order_id, '_wc_loyalty_choice', $choice );
	error_log( "WC Loyalty Coupon: Saved choice for order $order_id: $choice" );

	if ( 'gift' === $choice ) {
		$email = isset( $_POST['wc_loyalty_email'] ) ? sanitize_email( $_POST['wc_loyalty_email'] ) : '';
		if ( $email ) {
			update_post_meta( $order_id, '_wc_loyalty_friend_email', $email );
			error_log( "WC Loyalty Coupon: Saved friend email for order $order_id: $email" );
		}
	}
}

/**
 * Create coupon on order status change
 */
function wc_loyalty_create_coupon( $order_id ) {
	error_log( "WC Loyalty Coupon: Creating coupon for order $order_id" );

	try {
		// Check if already processed
		if ( get_post_meta( $order_id, '_wc_loyalty_processed', true ) ) {
			error_log( "WC Loyalty Coupon: Order $order_id already processed" );
			return;
		}

		// Get order
		if ( ! function_exists( 'wc_get_order' ) ) {
			error_log( "WC Loyalty Coupon: wc_get_order function not available" );
			return;
		}

		$order = wc_get_order( $order_id );
		if ( ! $order ) {
			error_log( "WC Loyalty Coupon: Could not get order $order_id" );
			return;
		}

		// Get the choice that was saved
		$choice = get_post_meta( $order_id, '_wc_loyalty_choice', true );
		error_log( "WC Loyalty Coupon: Order $order_id choice: $choice" );

		// Check if qualifies
		$total = floatval( $order->get_total() );
		$min = floatval( get_option( 'wc_loyalty_coupon_min_amount', 250 ) );

		error_log( "WC Loyalty Coupon: Order $order_id total: $total, min: $min" );

		if ( $total < $min ) {
			error_log( "WC Loyalty Coupon: Order $order_id doesn't qualify (total < min)" );
			return;
		}

		// Get settings
		$amount = floatval( get_option( 'wc_loyalty_coupon_amount', 35 ) );
		$days = intval( get_option( 'wc_loyalty_coupon_days_valid', 30 ) );

		// Generate code
		$code = 'LOYALTY-' . $order_id . '-' . strtoupper( substr( md5( time() ), 0, 6 ) );

		// Create coupon
		if ( ! class_exists( 'WC_Coupon' ) ) {
			error_log( "WC Loyalty Coupon: WC_Coupon class not available" );
			return;
		}

		$coupon = new WC_Coupon();
		$coupon->set_code( $code );
		$coupon->set_discount_type( 'fixed_cart' );
		$coupon->set_amount( $amount );
		$coupon->set_usage_limit( 1 );
		$coupon->set_usage_limit_per_user( 1 );
		$coupon->set_individual_use( true );

		// Get recipient
		if ( 'gift' === $choice ) {
			$recipient = get_post_meta( $order_id, '_wc_loyalty_friend_email', true );
		} else {
			$recipient = $order->get_billing_email();
		}

		error_log( "WC Loyalty Coupon: Recipient for order $order_id: $recipient" );

		if ( ! $recipient ) {
			error_log( "WC Loyalty Coupon: No recipient found for order $order_id" );
			return;
		}

		// Set restrictions
		$coupon->set_email_restrictions( array( $recipient ) );
		$coupon->set_date_expires( strtotime( "+$days days" ) );

		// Save coupon
		$coupon_id = $coupon->save();
		if ( ! $coupon_id ) {
			error_log( "WC Loyalty Coupon: Failed to save coupon for order $order_id" );
			return;
		}

		error_log( "WC Loyalty Coupon: Coupon created! ID: $coupon_id, Code: $code" );

		// Mark as processed
		update_post_meta( $order_id, '_wc_loyalty_processed', '1' );
		update_post_meta( $coupon_id, '_wc_loyalty_order_id', $order_id );

		// Send email
		$subject = 'Your $' . number_format( $amount, 2 ) . ' Coupon';
		$message = "You've received a coupon!\n\n";
		$message .= "Code: $code\n";
		$message .= "Discount: $" . number_format( $amount, 2 ) . "\n";
		$message .= "Expires: " . date( 'Y-m-d', strtotime( "+$days days" ) ) . "\n\n";
		$message .= "Use it at checkout!";

		if ( function_exists( 'wp_mail' ) ) {
			$sent = wp_mail( $recipient, $subject, $message );
			error_log( "WC Loyalty Coupon: Email sent to $recipient for order $order_id: " . ( $sent ? 'success' : 'failed' ) );
		} else {
			error_log( "WC Loyalty Coupon: wp_mail function not available" );
		}

	} catch ( Exception $e ) {
		error_log( 'WC Loyalty Coupon Error: ' . $e->getMessage() );
	}
}

/**
 * Admin menu
 */
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

/**
 * Admin init
 */
function wc_loyalty_admin_init() {
	register_setting( 'wc_loyalty_coupon_group', 'wc_loyalty_coupon_amount', array( 'sanitize_callback' => 'floatval' ) );
	register_setting( 'wc_loyalty_coupon_group', 'wc_loyalty_coupon_min_amount', array( 'sanitize_callback' => 'floatval' ) );
	register_setting( 'wc_loyalty_coupon_group', 'wc_loyalty_coupon_days_valid', array( 'sanitize_callback' => 'intval' ) );
}

/**
 * Admin page
 */
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
