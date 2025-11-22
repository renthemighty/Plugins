<?php
/**
 * Plugin Name: WooCommerce Loyalty Coupon
 * Description: Automatically issue $35 coupons for next purchase when customers spend over $250
 * Version: 1.0.4
 * Author: Your Name
 * License: GPL v2 or later
 * Text Domain: wc-loyalty-coupon
 * Domain Path: /languages
 * Requires at least: 5.0
 * Requires PHP: 7.4
 */

if ( ! defined( 'ABSPATH' ) ) {
	exit;
}

// Set default options on activation
register_activation_hook( __FILE__, function() {
	add_option( 'wc_loyalty_coupon_amount', 35 );
	add_option( 'wc_loyalty_coupon_min_amount', 250 );
	add_option( 'wc_loyalty_coupon_days_valid', 30 );
});

// Main plugin initialization
add_action( 'plugins_loaded', function() {
	// Check WooCommerce is active
	if ( ! function_exists( 'WC' ) || ! function_exists( 'wc_get_order' ) ) {
		return;
	}

	// Only load on frontend, not admin
	if ( is_admin() ) {
		add_action( 'admin_menu', 'wc_loyalty_coupon_add_admin_menu' );
		add_action( 'admin_init', 'wc_loyalty_coupon_register_settings' );
		return;
	}

	// Checkout hooks
	add_action( 'woocommerce_checkout_init', 'wc_loyalty_coupon_checkout_init' );
	add_action( 'woocommerce_checkout_process', 'wc_loyalty_coupon_validate_checkout' );
	add_action( 'woocommerce_checkout_update_order_meta', 'wc_loyalty_coupon_save_order_meta' );

	// Order completion
	add_action( 'woocommerce_order_status_completed', 'wc_loyalty_coupon_on_order_completed' );

}, 20 );

/**
 * Initialize checkout
 */
function wc_loyalty_coupon_checkout_init() {
	// Add hidden input fields and form
	add_action( 'woocommerce_before_checkout_form', 'wc_loyalty_coupon_render_form', 5 );
}

/**
 * Render the loyalty coupon form
 */
function wc_loyalty_coupon_render_form() {
	try {
		$cart = WC()->cart;
		if ( ! $cart ) {
			return;
		}

		$total = floatval( $cart->get_total( false ) );
		$min_amount = floatval( get_option( 'wc_loyalty_coupon_min_amount', 250 ) );

		if ( $total < $min_amount ) {
			return;
		}

		$amount = floatval( get_option( 'wc_loyalty_coupon_amount', 35 ) );
		$choice = isset( $_POST['wc_loyalty_choice'] ) ? sanitize_text_field( $_POST['wc_loyalty_choice'] ) : 'keep';
		$email = isset( $_POST['wc_loyalty_email'] ) ? sanitize_email( $_POST['wc_loyalty_email'] ) : '';
		?>
		<div style="background: #f5f5f5; padding: 20px; margin: 20px 0; border-left: 4px solid #0073aa; border-radius: 4px;">
			<h3>You've Earned a $<?php echo number_format( $amount, 2 ); ?> Loyalty Coupon!</h3>
			<p>What would you like to do with it?</p>

			<label style="display:block; margin:10px 0;">
				<input type="radio" name="wc_loyalty_choice" value="keep" <?php checked( $choice, 'keep' ); ?> onchange="toggleEmail()" />
				Keep it for my next purchase
			</label>

			<label style="display:block; margin:10px 0;">
				<input type="radio" name="wc_loyalty_choice" value="gift" <?php checked( $choice, 'gift' ); ?> onchange="toggleEmail()" />
				Send it to a friend
			</label>

			<div id="friend_email_div" style="display:<?php echo $choice === 'gift' ? 'block' : 'none'; ?>; margin:15px 0;">
				<label>Friend's Email:</label>
				<input type="email" name="wc_loyalty_email" placeholder="friend@example.com" value="<?php echo esc_attr( $email ); ?>" style="width:100%; padding:8px; box-sizing:border-box;" />
			</div>
		</div>
		<script>
			function toggleEmail() {
				var choice = document.querySelector('input[name="wc_loyalty_choice"]:checked');
				var div = document.getElementById('friend_email_div');
				if ( choice && choice.value === 'gift' ) {
					div.style.display = 'block';
				} else {
					div.style.display = 'none';
				}
			}
		</script>
		<?php
	} catch ( Exception $e ) {
		error_log( 'WC Loyalty Coupon render error: ' . $e->getMessage() );
	}
}

/**
 * Validate checkout
 */
function wc_loyalty_coupon_validate_checkout() {
	try {
		$cart = WC()->cart;
		if ( ! $cart ) {
			return;
		}

		$total = floatval( $cart->get_total( false ) );
		$min_amount = floatval( get_option( 'wc_loyalty_coupon_min_amount', 250 ) );

		if ( $total < $min_amount ) {
			return;
		}

		$choice = isset( $_POST['wc_loyalty_choice'] ) ? sanitize_text_field( $_POST['wc_loyalty_choice'] ) : 'keep';

		if ( 'gift' === $choice ) {
			$email = isset( $_POST['wc_loyalty_email'] ) ? sanitize_email( $_POST['wc_loyalty_email'] ) : '';
			if ( ! $email || ! is_email( $email ) ) {
				wc_add_notice( 'Please enter a valid email for your friend.', 'error' );
			}
		}
	} catch ( Exception $e ) {
		error_log( 'WC Loyalty Coupon validation error: ' . $e->getMessage() );
	}
}

/**
 * Save order metadata
 */
function wc_loyalty_coupon_save_order_meta( $order_id ) {
	try {
		$cart = WC()->cart;
		if ( ! $cart ) {
			return;
		}

		$total = floatval( $cart->get_total( false ) );
		$min_amount = floatval( get_option( 'wc_loyalty_coupon_min_amount', 250 ) );

		if ( $total < $min_amount ) {
			return;
		}

		$choice = isset( $_POST['wc_loyalty_choice'] ) ? sanitize_text_field( $_POST['wc_loyalty_choice'] ) : 'keep';
		update_post_meta( $order_id, '_wc_loyalty_choice', $choice );

		if ( 'gift' === $choice ) {
			$email = isset( $_POST['wc_loyalty_email'] ) ? sanitize_email( $_POST['wc_loyalty_email'] ) : '';
			update_post_meta( $order_id, '_wc_loyalty_friend_email', $email );
		}
	} catch ( Exception $e ) {
		error_log( 'WC Loyalty Coupon save error: ' . $e->getMessage() );
	}
}

/**
 * Process order completion
 */
function wc_loyalty_coupon_on_order_completed( $order_id ) {
	try {
		if ( get_post_meta( $order_id, '_wc_loyalty_processed', true ) ) {
			return;
		}

		$order = wc_get_order( $order_id );
		if ( ! $order ) {
			return;
		}

		$total = floatval( $order->get_total() );
		$min_amount = floatval( get_option( 'wc_loyalty_coupon_min_amount', 250 ) );

		if ( $total < $min_amount ) {
			return;
		}

		// Create coupon
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

		// Determine recipient
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

		$result = $coupon->save();

		if ( $result ) {
			update_post_meta( $order_id, '_wc_loyalty_processed', '1' );
			update_post_meta( $coupon->get_id(), '_wc_loyalty_order_id', $order_id );

			// Send email
			$subject = $amount . ' Coupon for You!';
			$message = "You've received a coupon for \$$amount!\n\n";
			$message .= "Code: $code\n";
			$message .= "Expires: " . date( 'Y-m-d', strtotime( "+$days days" ) ) . "\n\n";
			$message .= "Use it at checkout!";

			wp_mail( $recipient, $subject, $message );
		}
	} catch ( Exception $e ) {
		error_log( 'WC Loyalty Coupon order error: ' . $e->getMessage() );
	}
}

/**
 * Add admin menu
 */
function wc_loyalty_coupon_add_admin_menu() {
	if ( ! current_user_can( 'manage_woocommerce' ) ) {
		return;
	}

	add_submenu_page(
		'woocommerce',
		'Loyalty Coupons',
		'Loyalty Coupons',
		'manage_woocommerce',
		'wc-loyalty-coupon',
		'wc_loyalty_coupon_admin_page'
	);
}

/**
 * Register settings
 */
function wc_loyalty_coupon_register_settings() {
	register_setting( 'wc_loyalty_coupon_group', 'wc_loyalty_coupon_amount', array( 'sanitize_callback' => 'floatval' ) );
	register_setting( 'wc_loyalty_coupon_group', 'wc_loyalty_coupon_min_amount', array( 'sanitize_callback' => 'floatval' ) );
	register_setting( 'wc_loyalty_coupon_group', 'wc_loyalty_coupon_days_valid', array( 'sanitize_callback' => 'intval' ) );
}

/**
 * Admin page
 */
function wc_loyalty_coupon_admin_page() {
	if ( ! current_user_can( 'manage_woocommerce' ) ) {
		wp_die( 'Unauthorized' );
	}

	$tab = isset( $_GET['tab'] ) ? sanitize_text_field( $_GET['tab'] ) : 'settings';
	?>
	<div class="wrap">
		<h1>WooCommerce Loyalty Coupons</h1>

		<nav class="nav-tab-wrapper">
			<a href="?page=wc-loyalty-coupon&tab=settings" class="nav-tab <?php echo 'settings' === $tab ? 'nav-tab-active' : ''; ?>">Settings</a>
		</nav>

		<div class="tab-content" style="background:#fff; padding:20px; border:1px solid #ccc;">
			<?php if ( 'settings' === $tab ) : ?>
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
			<?php endif; ?>
		</div>
	</div>
	<?php
}
