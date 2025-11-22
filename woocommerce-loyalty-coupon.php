<?php
/**
 * Plugin Name: WooCommerce Loyalty Coupon
 * Description: Automatically issue $35 coupons for next purchase when customers spend over $250
 * Version: 1.0.1
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
	if ( ! get_option( 'wc_loyalty_coupon_amount' ) ) {
		add_option( 'wc_loyalty_coupon_amount', 35 );
	}
	if ( ! get_option( 'wc_loyalty_coupon_min_amount' ) ) {
		add_option( 'wc_loyalty_coupon_min_amount', 250 );
	}
	if ( ! get_option( 'wc_loyalty_coupon_days_valid' ) ) {
		add_option( 'wc_loyalty_coupon_days_valid', 30 );
	}
} );

// Main plugin initialization
add_action( 'plugins_loaded', function() {
	// Check WooCommerce is active
	if ( ! function_exists( 'WC' ) ) {
		return;
	}

	// Checkout hooks
	add_action( 'woocommerce_before_checkout_form', 'wc_loyalty_coupon_gift_section' );
	add_action( 'woocommerce_checkout_process', 'wc_loyalty_coupon_validate_gift' );
	add_action( 'woocommerce_checkout_update_order_meta', 'wc_loyalty_coupon_save_gift_meta' );

	// Cart and checkout notices
	add_action( 'woocommerce_before_cart', 'wc_loyalty_coupon_cart_notice' );
	add_action( 'woocommerce_before_checkout_form', 'wc_loyalty_coupon_checkout_notice' );

	// Hook into order completion
	add_action( 'woocommerce_order_status_completed', 'wc_loyalty_coupon_create_coupon' );

	// Email hooks
	add_filter( 'woocommerce_email_classes', 'wc_loyalty_coupon_register_emails' );
	add_action( 'woocommerce_order_status_completed', 'wc_loyalty_coupon_send_coupon_email' );

	// Admin hooks
	if ( is_admin() ) {
		add_action( 'admin_menu', 'wc_loyalty_coupon_add_menu' );
		add_action( 'admin_init', 'wc_loyalty_coupon_register_settings' );
		add_action( 'admin_post_wc_loyalty_delete', 'wc_loyalty_coupon_delete_coupon' );
	}
}, 20 );

/**
 * Ensure email classes are loaded and registered
 */
function wc_loyalty_coupon_load_email_classes() {
	if ( ! class_exists( 'WC_Loyalty_Coupon_Email_Personal' ) ) {
		include plugin_dir_path( __FILE__ ) . 'emails/class-wc-loyalty-coupon-email-personal.php';
	}
	if ( ! class_exists( 'WC_Loyalty_Coupon_Email_Gift' ) ) {
		include plugin_dir_path( __FILE__ ) . 'emails/class-wc-loyalty-coupon-email-gift.php';
	}
}

/**
 * Register custom email classes
 */
function wc_loyalty_coupon_register_emails( $emails ) {
	wc_loyalty_coupon_load_email_classes();

	$emails['WC_Loyalty_Coupon_Email_Personal'] = new WC_Loyalty_Coupon_Email_Personal();
	$emails['WC_Loyalty_Coupon_Email_Gift'] = new WC_Loyalty_Coupon_Email_Gift();

	return $emails;
}

/**
 * Send coupon email via WooCommerce
 */
function wc_loyalty_coupon_send_coupon_email( $order_id ) {
	// Wait a moment for coupon to be fully saved
	sleep( 1 );

	$order = wc_get_order( $order_id );

	if ( ! $order ) {
		error_log( "WC Loyalty Coupon: Order $order_id not found" );
		return;
	}

	// Get gift choice
	$gift_choice = get_post_meta( $order_id, '_loyalty_gift_choice', true );

	// Get coupon info - look for most recently created coupon for this order
	$args = array(
		'post_type'      => 'shop_coupon',
		'posts_per_page' => 1,
		'orderby'        => 'ID',
		'order'          => 'DESC',
		'meta_query'     => array(
			array(
				'key'   => '_loyalty_order_id',
				'value' => $order_id,
			),
		),
	);

	$query = new WP_Query( $args );

	if ( ! $query->have_posts() ) {
		error_log( "WC Loyalty Coupon: No coupon found for order $order_id" );
		return;
	}

	$coupon_post = $query->posts[0];
	$coupon = new WC_Coupon( $coupon_post->ID );

	if ( ! $coupon || ! $coupon->get_code() ) {
		error_log( "WC Loyalty Coupon: Coupon object invalid for order $order_id" );
		return;
	}

	// Determine recipient
	if ( 'friend' === $gift_choice ) {
		$recipient_email = get_post_meta( $order_id, '_loyalty_friend_email', true );
		$is_gift = true;
	} else {
		$recipient_email = $order->get_billing_email();
		$is_gift = false;
	}

	if ( ! $recipient_email ) {
		error_log( "WC Loyalty Coupon: No recipient email for order $order_id" );
		return;
	}

	// Load email classes
	wc_loyalty_coupon_load_email_classes();

	// Send via WC email system
	try {
		$mailer = WC()->mailer();

		if ( ! is_object( $mailer ) || ! property_exists( $mailer, 'emails' ) ) {
			error_log( "WC Loyalty Coupon: Mailer not available for order $order_id" );
			return;
		}

		$email_sent = false;

		if ( $is_gift ) {
			// Gift email
			if ( isset( $mailer->emails['WC_Loyalty_Coupon_Email_Gift'] ) ) {
				$email = $mailer->emails['WC_Loyalty_Coupon_Email_Gift'];
				$email->trigger( $order_id, $coupon, $recipient_email );
				$email_sent = true;
				error_log( "WC Loyalty Coupon: Gift email sent to $recipient_email for order $order_id" );
			} else {
				// Fallback to foreach
				foreach ( $mailer->emails as $email ) {
					if ( is_a( $email, 'WC_Loyalty_Coupon_Email_Gift' ) ) {
						$email->trigger( $order_id, $coupon, $recipient_email );
						$email_sent = true;
						error_log( "WC Loyalty Coupon: Gift email sent (via loop) to $recipient_email for order $order_id" );
						break;
					}
				}
			}
		} else {
			// Personal email
			if ( isset( $mailer->emails['WC_Loyalty_Coupon_Email_Personal'] ) ) {
				$email = $mailer->emails['WC_Loyalty_Coupon_Email_Personal'];
				$email->trigger( $order_id, $coupon, $recipient_email );
				$email_sent = true;
				error_log( "WC Loyalty Coupon: Personal email sent to $recipient_email for order $order_id" );
			} else {
				// Fallback to foreach
				foreach ( $mailer->emails as $email ) {
					if ( is_a( $email, 'WC_Loyalty_Coupon_Email_Personal' ) ) {
						$email->trigger( $order_id, $coupon, $recipient_email );
						$email_sent = true;
						error_log( "WC Loyalty Coupon: Personal email sent (via loop) to $recipient_email for order $order_id" );
						break;
					}
				}
			}
		}

		if ( ! $email_sent ) {
			error_log( "WC Loyalty Coupon: Email class not found in mailer for order $order_id" );
		}
	} catch ( Exception $e ) {
		error_log( 'WC Loyalty Coupon Email Error for order ' . $order_id . ': ' . $e->getMessage() );
	}
}

/**
 * Display cart notice if qualifies
 */
function wc_loyalty_coupon_cart_notice() {
	$cart_total = WC()->cart->get_total( false );
	$min_amount = (float) get_option( 'wc_loyalty_coupon_min_amount', 250 );
	$coupon_amount = (float) get_option( 'wc_loyalty_coupon_amount', 35 );

	if ( $cart_total >= $min_amount ) {
		wc_print_notice(
			sprintf(
				'🎁 <strong>Great news!</strong> Your cart qualifies for a <strong>$%s loyalty gift coupon</strong>! At checkout, you can choose to keep it or send it to a friend.',
				number_format( $coupon_amount, 2 )
			),
			'success'
		);
	}
}

/**
 * Display checkout notice if qualifies
 */
function wc_loyalty_coupon_checkout_notice() {
	$cart_total = WC()->cart->get_total( false );
	$min_amount = (float) get_option( 'wc_loyalty_coupon_min_amount', 250 );
	$coupon_amount = (float) get_option( 'wc_loyalty_coupon_amount', 35 );

	if ( $cart_total >= $min_amount ) {
		wc_print_notice(
			sprintf(
				'🎁 <strong>You Qualify!</strong> You\'ll receive a <strong>$%s loyalty coupon</strong> for your next purchase after you complete this order. Choose below to keep it or give it to a friend!',
				number_format( $coupon_amount, 2 )
			),
			'success'
		);
	}
}

/**
 * Add gift section to checkout
 */
function wc_loyalty_coupon_gift_section() {
	$cart_total = WC()->cart->get_total( false );
	$min_amount = (float) get_option( 'wc_loyalty_coupon_min_amount', 250 );

	if ( $cart_total < $min_amount ) {
		return;
	}

	$coupon_amount = (float) get_option( 'wc_loyalty_coupon_amount', 35 );
	$gift_choice = isset( $_POST['wc_loyalty_gift_choice'] ) ? sanitize_text_field( $_POST['wc_loyalty_gift_choice'] ) : 'keep';
	$friend_email = isset( $_POST['wc_loyalty_friend_email'] ) ? sanitize_email( $_POST['wc_loyalty_friend_email'] ) : '';
	?>
	<div id="wc_loyalty_gift_section" style="background: #f5f5f5; padding: 20px; margin: 20px 0; border-left: 4px solid #0073aa; border-radius: 4px;">
		<h3 style="margin-top: 0;">Your Loyalty Gift - $<?php echo number_format( $coupon_amount, 2 ); ?> Coupon</h3>
		<p>You've earned a loyalty coupon! How would you like to use it?</p>

		<div style="margin: 15px 0;">
			<label style="display: block; margin-bottom: 10px;">
				<input type="radio" name="wc_loyalty_gift_choice" value="keep" <?php checked( $gift_choice, 'keep' ); ?> onchange="wc_loyalty_toggle_friend_email()" />
				<strong>Keep it for myself</strong>
				<span style="color: #666; font-size: 14px; display: block; margin-left: 24px;">The coupon will be sent to your email address</span>
			</label>

			<label style="display: block; margin-bottom: 10px;">
				<input type="radio" name="wc_loyalty_gift_choice" value="friend" <?php checked( $gift_choice, 'friend' ); ?> onchange="wc_loyalty_toggle_friend_email()" />
				<strong>Send it to a friend</strong>
				<span style="color: #666; font-size: 14px; display: block; margin-left: 24px;">Share the love and spread the savings!</span>
			</label>
		</div>

		<div id="wc_loyalty_friend_email_field" style="display: <?php echo 'friend' === $gift_choice ? 'block' : 'none'; ?>; margin: 15px 0;">
			<label for="wc_loyalty_friend_email" style="display: block; margin-bottom: 8px; font-weight: bold;">Friend's Email Address</label>
			<input type="email" id="wc_loyalty_friend_email" name="wc_loyalty_friend_email" placeholder="friend@example.com" value="<?php echo esc_attr( $friend_email ); ?>" style="width: 100%; padding: 10px; border: 1px solid #ddd; border-radius: 4px; box-sizing: border-box;" />
			<p style="font-size: 13px; color: #666; margin: 5px 0 0;">They'll receive an email with the coupon code after your order is complete.</p>
		</div>
	</div>

	<script type="text/javascript">
		function wc_loyalty_toggle_friend_email() {
			var choice = document.querySelector('input[name="wc_loyalty_gift_choice"]:checked').value;
			var emailField = document.getElementById('wc_loyalty_friend_email_field');
			if ( choice === 'friend' ) {
				emailField.style.display = 'block';
				document.getElementById('wc_loyalty_friend_email').required = true;
			} else {
				emailField.style.display = 'none';
				document.getElementById('wc_loyalty_friend_email').required = false;
			}
		}
	</script>
	<?php
}

/**
 * Validate gift field at checkout
 */
function wc_loyalty_coupon_validate_gift() {
	$cart_total = WC()->cart->get_total( false );
	$min_amount = (float) get_option( 'wc_loyalty_coupon_min_amount', 250 );

	if ( $cart_total < $min_amount ) {
		return;
	}

	$gift_choice = isset( $_POST['wc_loyalty_gift_choice'] ) ? sanitize_text_field( $_POST['wc_loyalty_gift_choice'] ) : 'keep';

	if ( 'friend' === $gift_choice ) {
		$friend_email = isset( $_POST['wc_loyalty_friend_email'] ) ? sanitize_email( $_POST['wc_loyalty_friend_email'] ) : '';

		if ( ! $friend_email || ! is_email( $friend_email ) ) {
			wc_add_notice( 'Please enter a valid email address for your friend.', 'error' );
		}
	}
}

/**
 * Save gift choice to order meta
 */
function wc_loyalty_coupon_save_gift_meta( $order_id ) {
	$cart_total = WC()->cart->get_total( false );
	$min_amount = (float) get_option( 'wc_loyalty_coupon_min_amount', 250 );

	if ( $cart_total < $min_amount ) {
		return;
	}

	$gift_choice = isset( $_POST['wc_loyalty_gift_choice'] ) ? sanitize_text_field( $_POST['wc_loyalty_gift_choice'] ) : 'keep';
	update_post_meta( $order_id, '_loyalty_gift_choice', $gift_choice );

	if ( 'friend' === $gift_choice ) {
		$friend_email = isset( $_POST['wc_loyalty_friend_email'] ) ? sanitize_email( $_POST['wc_loyalty_friend_email'] ) : '';
		update_post_meta( $order_id, '_loyalty_friend_email', $friend_email );
	}
}

/**
 * Create loyalty coupon on order completion
 */
function wc_loyalty_coupon_create_coupon( $order_id ) {
	$order = wc_get_order( $order_id );

	if ( ! $order ) {
		error_log( "WC Loyalty Coupon: Order $order_id not found for coupon creation" );
		return;
	}

	// Skip if already processed
	if ( get_post_meta( $order_id, '_loyalty_coupon_created', true ) ) {
		error_log( "WC Loyalty Coupon: Coupon already created for order $order_id" );
		return;
	}

	$min_amount = (float) get_option( 'wc_loyalty_coupon_min_amount', 250 );

	if ( $order->get_total() < $min_amount ) {
		update_post_meta( $order_id, '_loyalty_coupon_created', 'no_match' );
		error_log( "WC Loyalty Coupon: Order $order_id total (" . $order->get_total() . ") below minimum ($min_amount)" );
		return;
	}

	$coupon_amount = (float) get_option( 'wc_loyalty_coupon_amount', 35 );
	$days_valid = (int) get_option( 'wc_loyalty_coupon_days_valid', 30 );

	// Determine recipient email based on gift choice
	$gift_choice = get_post_meta( $order_id, '_loyalty_gift_choice', true );
	if ( 'friend' === $gift_choice ) {
		$recipient_email = get_post_meta( $order_id, '_loyalty_friend_email', true );
	} else {
		$recipient_email = $order->get_billing_email();
	}

	if ( ! $recipient_email ) {
		error_log( "WC Loyalty Coupon: No recipient email for order $order_id" );
		return;
	}

	// Generate unique code
	$code = 'LOYALTY-' . $order_id . '-' . strtoupper( substr( md5( wp_rand() ), 0, 6 ) );

	// Create coupon
	$coupon = new WC_Coupon();
	$coupon->set_code( $code );
	$coupon->set_discount_type( 'fixed_cart' );
	$coupon->set_amount( $coupon_amount );
	$coupon->set_usage_limit( 1 );
	$coupon->set_usage_limit_per_user( 1 );
	$coupon->set_individual_use( true );
	$coupon->set_email_restrictions( array( $recipient_email ) );

	$expiry = strtotime( "+{$days_valid} days" );
	$coupon->set_date_expires( $expiry );

	$result = $coupon->save();

	if ( $result ) {
		$coupon_id = $coupon->get_id();
		update_post_meta( $order_id, '_loyalty_coupon_created', current_time( 'mysql' ) );
		update_post_meta( $coupon_id, '_loyalty_order_id', $order_id );
		error_log( "WC Loyalty Coupon: Coupon $coupon_id ($code) created for order $order_id, recipient: $recipient_email" );
		// Email will be sent via wc_loyalty_coupon_send_coupon_email action
	} else {
		error_log( "WC Loyalty Coupon: Failed to save coupon for order $order_id" );
	}
}

/**
 * Add admin menu
 */
function wc_loyalty_coupon_add_menu() {
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
	register_setting(
		'wc_loyalty_coupon_group',
		'wc_loyalty_coupon_amount',
		array( 'sanitize_callback' => 'floatval' )
	);
	register_setting(
		'wc_loyalty_coupon_group',
		'wc_loyalty_coupon_min_amount',
		array( 'sanitize_callback' => 'floatval' )
	);
	register_setting(
		'wc_loyalty_coupon_group',
		'wc_loyalty_coupon_days_valid',
		array( 'sanitize_callback' => 'intval' )
	);
}

/**
 * Admin page
 */
function wc_loyalty_coupon_admin_page() {
	if ( ! current_user_can( 'manage_woocommerce' ) ) {
		wp_die( 'Unauthorized' );
	}

	$tab = isset( $_GET['tab'] ) ? sanitize_text_field( $_GET['tab'] ) : 'dashboard';
	$nonce = wp_create_nonce( 'wc_loyalty_coupon_nonce' );
	?>
	<div class="wrap">
		<h1>WooCommerce Loyalty Coupons</h1>

		<nav class="nav-tab-wrapper">
			<a href="?page=wc-loyalty-coupon&tab=dashboard" class="nav-tab <?php echo 'dashboard' === $tab ? 'nav-tab-active' : ''; ?>">Dashboard</a>
			<a href="?page=wc-loyalty-coupon&tab=coupons" class="nav-tab <?php echo 'coupons' === $tab ? 'nav-tab-active' : ''; ?>">Coupons</a>
			<a href="?page=wc-loyalty-coupon&tab=settings" class="nav-tab <?php echo 'settings' === $tab ? 'nav-tab-active' : ''; ?>">Settings</a>
		</nav>

		<div class="tab-content">
			<?php
			if ( 'coupons' === $tab ) {
				wc_loyalty_coupon_show_coupons();
			} elseif ( 'settings' === $tab ) {
				wc_loyalty_coupon_show_settings();
			} else {
				wc_loyalty_coupon_show_dashboard();
			}
			?>
		</div>
	</div>

	<style>
		.nav-tab-wrapper {
			background: #fff;
			border-bottom: 1px solid #ccc;
			padding: 0;
			margin: 0;
		}
		.nav-tab {
			background: #f0f0f0;
			border: 1px solid #ccc;
			border-bottom: none;
			color: #0073aa;
			padding: 12px 24px;
			text-decoration: none;
			display: inline-block;
		}
		.nav-tab-active {
			background: #fff;
			border-bottom: 1px solid #fff;
			color: #0073aa;
			font-weight: bold;
		}
		.tab-content {
			background: #fff;
			padding: 20px;
			border: 1px solid #ccc;
			border-top: none;
		}
		.stat-box {
			display: inline-block;
			background: #f5f5f5;
			padding: 20px;
			margin-right: 20px;
			margin-bottom: 20px;
			border-left: 4px solid #0073aa;
			min-width: 200px;
		}
		.stat-box h3 {
			margin: 0 0 10px;
			font-size: 13px;
			color: #999;
			text-transform: uppercase;
		}
		.stat-box .value {
			font-size: 32px;
			font-weight: bold;
			color: #333;
		}
		table {
			width: 100%;
			border-collapse: collapse;
			margin-top: 20px;
		}
		table th, table td {
			padding: 12px;
			text-align: left;
			border-bottom: 1px solid #ddd;
		}
		table th {
			background: #f5f5f5;
			font-weight: bold;
		}
		table tr:hover {
			background: #f9f9f9;
		}
		.button {
			margin-right: 10px;
		}
	</style>
	<?php
}

/**
 * Show dashboard tab
 */
function wc_loyalty_coupon_show_dashboard() {
	$coupons = wc_loyalty_get_all_coupons();
	$used = 0;
	$total_value = 0;

	foreach ( $coupons as $coupon ) {
		$total_value += $coupon['amount'];
		if ( $coupon['used'] ) {
			$used++;
		}
	}
	?>
	<div class="stat-box">
		<h3>Total Coupons</h3>
		<div class="value"><?php echo count( $coupons ); ?></div>
	</div>
	<div class="stat-box">
		<h3>Used</h3>
		<div class="value"><?php echo $used; ?></div>
	</div>
	<div class="stat-box">
		<h3>Unused</h3>
		<div class="value"><?php echo count( $coupons ) - $used; ?></div>
	</div>
	<div class="stat-box">
		<h3>Total Value</h3>
		<div class="value">$<?php echo number_format( $total_value, 2 ); ?></div>
	</div>

	<h2>Recent Coupons</h2>
	<?php
	if ( empty( $coupons ) ) {
		echo '<p>No loyalty coupons yet.</p>';
	} else {
		wc_loyalty_coupon_table( array_slice( $coupons, 0, 10 ) );
	}
}

/**
 * Show coupons tab
 */
function wc_loyalty_coupon_show_coupons() {
	$coupons = wc_loyalty_get_all_coupons();
	?>
	<h2>All Loyalty Coupons</h2>
	<?php
	if ( empty( $coupons ) ) {
		echo '<p>No loyalty coupons yet.</p>';
	} else {
		wc_loyalty_coupon_table( $coupons );
	}
}

/**
 * Show settings tab
 */
function wc_loyalty_coupon_show_settings() {
	?>
	<form method="post" action="options.php">
		<?php settings_fields( 'wc_loyalty_coupon_group' ); ?>
		<table class="form-table">
			<tr>
				<th scope="row"><label for="wc_loyalty_coupon_amount">Coupon Amount ($)</label></th>
				<td><input type="number" step="0.01" id="wc_loyalty_coupon_amount" name="wc_loyalty_coupon_amount" value="<?php echo esc_attr( get_option( 'wc_loyalty_coupon_amount', 35 ) ); ?>" /></td>
			</tr>
			<tr>
				<th scope="row"><label for="wc_loyalty_coupon_min_amount">Minimum Order Amount ($)</label></th>
				<td><input type="number" step="0.01" id="wc_loyalty_coupon_min_amount" name="wc_loyalty_coupon_min_amount" value="<?php echo esc_attr( get_option( 'wc_loyalty_coupon_min_amount', 250 ) ); ?>" /></td>
			</tr>
			<tr>
				<th scope="row"><label for="wc_loyalty_coupon_days_valid">Coupon Valid (Days)</label></th>
				<td><input type="number" id="wc_loyalty_coupon_days_valid" name="wc_loyalty_coupon_days_valid" value="<?php echo esc_attr( get_option( 'wc_loyalty_coupon_days_valid', 30 ) ); ?>" min="1" /></td>
			</tr>
		</table>
		<?php submit_button(); ?>
	</form>
	<?php
}

/**
 * Display coupon table
 */
function wc_loyalty_coupon_table( $coupons ) {
	?>
	<table>
		<thead>
			<tr>
				<th>Code</th>
				<th>Amount</th>
				<th>Type</th>
				<th>Recipient</th>
				<th>Created</th>
				<th>Expires</th>
				<th>Status</th>
				<th>Action</th>
			</tr>
		</thead>
		<tbody>
			<?php
			foreach ( $coupons as $coupon ) {
				$delete_url = wp_nonce_url(
					add_query_arg( array( 'action' => 'wc_loyalty_delete', 'id' => $coupon['id'] ), admin_url( 'admin-post.php' ) ),
					'wc_loyalty_delete_' . $coupon['id']
				);
				$type_badge = 'Gift' === $coupon['type'] ? '<span style="background: #2271b1; color: white; padding: 2px 8px; border-radius: 3px; font-size: 12px;">🎁 Gift</span>' : '<span style="background: #117722; color: white; padding: 2px 8px; border-radius: 3px; font-size: 12px;">Personal</span>';
				?>
				<tr>
					<td><strong><?php echo esc_html( $coupon['code'] ); ?></strong></td>
					<td>$<?php echo number_format( $coupon['amount'], 2 ); ?></td>
					<td><?php echo $type_badge; ?></td>
					<td><?php echo esc_html( $coupon['recipient'] ); ?></td>
					<td><?php echo esc_html( $coupon['created'] ); ?></td>
					<td><?php echo esc_html( $coupon['expires'] ); ?></td>
					<td><?php echo $coupon['used'] ? '<span style="color: green;">✓ Used</span>' : '<span style="color: orange;">⏱ Unused</span>'; ?></td>
					<td><a href="<?php echo esc_url( $delete_url ); ?>" class="button button-small" onclick="return confirm('Delete this coupon?');">Delete</a></td>
				</tr>
				<?php
			}
			?>
		</tbody>
	</table>
	<?php
}

/**
 * Get all loyalty coupons
 */
function wc_loyalty_get_all_coupons() {
	$args = array(
		'post_type'      => 'shop_coupon',
		'posts_per_page' => -1,
		'orderby'        => 'ID',
		'order'          => 'DESC',
	);

	$query = new WP_Query( $args );
	$results = array();

	foreach ( $query->posts as $post ) {
		// Only include loyalty coupons
		$order_id = get_post_meta( $post->ID, '_loyalty_order_id', true );
		if ( ! $order_id ) {
			continue;
		}

		$coupon = new WC_Coupon( $post->ID );
		$order = wc_get_order( $order_id );
		$gift_choice = get_post_meta( $order_id, '_loyalty_gift_choice', true );
		$friend_email = get_post_meta( $order_id, '_loyalty_friend_email', true );

		$recipient = 'Unknown';
		$type = 'Personal';

		if ( 'friend' === $gift_choice && $friend_email ) {
			$recipient = $friend_email;
			$type = 'Gift';
		} elseif ( $order ) {
			$recipient = $order->get_billing_email();
		}

		$results[] = array(
			'id'        => $post->ID,
			'code'      => $coupon->get_code(),
			'amount'    => $coupon->get_amount(),
			'created'   => get_the_time( 'Y-m-d H:i', $post->ID ),
			'expires'   => $coupon->get_date_expires() ? $coupon->get_date_expires()->format( 'Y-m-d' ) : 'Never',
			'used'      => $coupon->get_usage_count() > 0,
			'type'      => $type,
			'recipient' => $recipient,
		);
	}

	return $results;
}

/**
 * Delete coupon
 */
function wc_loyalty_coupon_delete_coupon() {
	if ( ! isset( $_GET['_wpnonce'] ) ) {
		wp_die( 'Nonce error' );
	}

	$coupon_id = isset( $_GET['id'] ) ? intval( $_GET['id'] ) : 0;
	$nonce = sanitize_text_field( $_GET['_wpnonce'] );

	if ( ! wp_verify_nonce( $nonce, 'wc_loyalty_delete_' . $coupon_id ) ) {
		wp_die( 'Nonce verification failed' );
	}

	if ( ! current_user_can( 'manage_woocommerce' ) ) {
		wp_die( 'Unauthorized' );
	}

	if ( $coupon_id ) {
		wp_delete_post( $coupon_id, true );
	}

	wp_redirect( add_query_arg( array( 'page' => 'wc-loyalty-coupon', 'tab' => 'coupons' ), admin_url( 'admin.php' ) ) );
	exit;
}
