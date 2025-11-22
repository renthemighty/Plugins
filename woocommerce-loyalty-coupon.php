<?php
/**
 * Plugin Name: WooCommerce Loyalty Coupon
 * Description: Automatically issue $35 coupons for next purchase when customers spend over $250
 * Version: 1.0.8
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
	error_log( 'WC Loyalty Coupon: Initializing plugin - Admin: ' . ( is_admin() ? 'yes' : 'no' ) );

	// Check if WooCommerce is active
	if ( ! function_exists( 'WC' ) || ! class_exists( 'WC_Coupon' ) ) {
		error_log( 'WC Loyalty Coupon: WooCommerce not active' );
		return;
	}

	// Register coupon creation hooks globally (must run on all requests)
	error_log( 'WC Loyalty Coupon: Registering coupon creation hooks' );
	add_action( 'woocommerce_payment_complete', 'wc_loyalty_create_coupon', 10, 1 );
	add_action( 'woocommerce_order_status_processing', 'wc_loyalty_create_coupon', 10, 1 );
	add_action( 'woocommerce_order_status_completed', 'wc_loyalty_create_coupon', 10, 1 );

	// Admin only hooks
	if ( is_admin() ) {
		error_log( 'WC Loyalty Coupon: Registering admin hooks' );
		add_action( 'admin_menu', 'wc_loyalty_admin_menu' );
		add_action( 'admin_init', 'wc_loyalty_admin_init' );
		add_action( 'add_meta_boxes', 'wc_loyalty_add_order_metabox' );
		return;
	}

	// Frontend only hooks
	error_log( 'WC Loyalty Coupon: Registering frontend hooks' );
	add_action( 'woocommerce_before_checkout_form', 'wc_loyalty_checkout_form' );
	add_action( 'woocommerce_checkout_process', 'wc_loyalty_validate_checkout' );
	add_action( 'woocommerce_checkout_update_order_meta', 'wc_loyalty_save_meta' );

	error_log( 'WC Loyalty Coupon: Plugin initialized successfully' );
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
	error_log( "WC Loyalty Coupon: *** CHECKOUT_FORM called - Checking if customer qualifies ***" );
	if ( ! wc_loyalty_qualifies() ) {
		error_log( "WC Loyalty Coupon: Customer does NOT qualify - hiding coupon form" );
		return;
	}

	error_log( "WC Loyalty Coupon: ✓ Customer QUALIFIES - rendering coupon form" );

	$amount = floatval( get_option( 'wc_loyalty_coupon_amount', 35 ) );
	$choice = isset( $_POST['wc_loyalty_choice'] ) ? sanitize_text_field( $_POST['wc_loyalty_choice'] ) : 'keep';
	$email = isset( $_POST['wc_loyalty_email'] ) ? sanitize_email( $_POST['wc_loyalty_email'] ) : '';

	error_log( "WC Loyalty Coupon: Form rendering - Choice: $choice, Email: " . ( $email ? $email : 'NONE' ) );
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
	error_log( "WC Loyalty Coupon: *** VALIDATE_CHECKOUT called ***" );
	if ( ! wc_loyalty_qualifies() ) {
		error_log( "WC Loyalty Coupon: Checkout validation - Customer does NOT qualify" );
		return;
	}

	$choice = isset( $_POST['wc_loyalty_choice'] ) ? sanitize_text_field( $_POST['wc_loyalty_choice'] ) : 'keep';
	error_log( "WC Loyalty Coupon: Checkout validation - Choice: $choice, POST has wc_loyalty_choice? " . ( isset( $_POST['wc_loyalty_choice'] ) ? 'YES' : 'NO' ) );

	if ( 'gift' === $choice ) {
		$email = isset( $_POST['wc_loyalty_email'] ) ? sanitize_email( $_POST['wc_loyalty_email'] ) : '';
		if ( ! $email || ! is_email( $email ) ) {
			error_log( "WC Loyalty Coupon: ✗ Invalid email for gift: '" . ( $email ? $email : 'EMPTY' ) . "'" );
			wc_add_notice( 'Please enter a valid email for your friend.', 'error' );
		} else {
			error_log( "WC Loyalty Coupon: ✓ Gift email validation passed: $email" );
		}
	}
}

/**
 * Save order meta
 */
function wc_loyalty_save_meta( $order_id ) {
	error_log( "WC Loyalty Coupon: *** SAVE_META called for order $order_id ***" );

	if ( ! wc_loyalty_qualifies() ) {
		error_log( "WC Loyalty Coupon: Order $order_id doesn't qualify (cart check)" );
		return;
	}

	$choice = isset( $_POST['wc_loyalty_choice'] ) ? sanitize_text_field( $_POST['wc_loyalty_choice'] ) : 'keep';
	error_log( "WC Loyalty Coupon: POST data - choice: " . print_r( $_POST['wc_loyalty_choice'] ?? 'NOT SET', true ) . ", email: " . print_r( $_POST['wc_loyalty_email'] ?? 'NOT SET', true ) );

	update_post_meta( $order_id, '_wc_loyalty_choice', $choice );
	error_log( "WC Loyalty Coupon: Saved choice for order $order_id: $choice" );

	if ( 'gift' === $choice ) {
		$email = isset( $_POST['wc_loyalty_email'] ) ? sanitize_email( $_POST['wc_loyalty_email'] ) : '';
		if ( $email ) {
			update_post_meta( $order_id, '_wc_loyalty_friend_email', $email );
			error_log( "WC Loyalty Coupon: Saved friend email for order $order_id: $email" );
		} else {
			error_log( "WC Loyalty Coupon: Gift choice but no email provided for order $order_id" );
		}
	}
}

/**
 * Create coupon on order status change
 */
function wc_loyalty_create_coupon( $order_id ) {
	error_log( "WC Loyalty Coupon: *** CREATE_COUPON HOOK TRIGGERED for order $order_id ***" );

	try {
		// Check if already processed
		$processed = get_post_meta( $order_id, '_wc_loyalty_processed', true );
		error_log( "WC Loyalty Coupon: Order $order_id - Already processed? " . ( $processed ? 'YES' : 'NO' ) );

		if ( $processed ) {
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
		error_log( "WC Loyalty Coupon: Order $order_id - Retrieved choice from meta: '" . ( $choice ? $choice : 'EMPTY' ) . "'" );

		if ( empty( $choice ) ) {
			error_log( "WC Loyalty Coupon: Order $order_id - NO CHOICE SAVED! Skipping coupon creation." );
			return;
		}

		// Check if qualifies
		$total = floatval( $order->get_total() );
		$min = floatval( get_option( 'wc_loyalty_coupon_min_amount', 250 ) );

		error_log( "WC Loyalty Coupon: Order $order_id total: $total, min: $min, qualifies: " . ( $total >= $min ? 'YES' : 'NO' ) );

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
			error_log( "WC Loyalty Coupon: Order $order_id is GIFT - Retrieved friend email: '" . ( $recipient ? $recipient : 'EMPTY' ) . "'" );
		} else {
			$recipient = $order->get_billing_email();
			error_log( "WC Loyalty Coupon: Order $order_id is PERSONAL - Retrieved billing email: '" . ( $recipient ? $recipient : 'EMPTY' ) . "'" );
		}

		error_log( "WC Loyalty Coupon: Final recipient for order $order_id: " . ( $recipient ? $recipient : 'NO RECIPIENT' ) );

		if ( ! $recipient ) {
			error_log( "WC Loyalty Coupon: ✗ CRITICAL: No recipient found for order $order_id - ABORTING coupon creation" );
			return;
		}

		// Set restrictions
		$coupon->set_email_restrictions( array( $recipient ) );
		$coupon->set_date_expires( strtotime( "+$days days" ) );

		// Save coupon
		error_log( "WC Loyalty Coupon: About to save coupon. Code: $code, Amount: $amount, Recipient: $recipient" );
		$coupon_id = $coupon->save();
		if ( ! $coupon_id ) {
			error_log( "WC Loyalty Coupon: ✗ FAILED to save coupon for order $order_id" );
			return;
		}

		error_log( "WC Loyalty Coupon: ✓ Coupon created! ID: $coupon_id, Code: $code, Amount: $amount" );

		// Mark as processed
		update_post_meta( $order_id, '_wc_loyalty_processed', '1' );
		update_post_meta( $coupon_id, '_wc_loyalty_order_id', $order_id );

		// Add admin order note showing coupon was created
		$note_text = sprintf(
			'Loyalty Coupon Created: %s | Amount: $%s | Type: %s | Recipient: %s | Expires: %s',
			$code,
			number_format( $amount, 2 ),
			( 'gift' === $choice ? 'Gift' : 'Personal' ),
			$recipient,
			date( 'Y-m-d', strtotime( "+$days days" ) )
		);
		$order->add_order_note( $note_text, false );
		error_log( "WC Loyalty Coupon: Added order note to order $order_id: $note_text" );

		// Send email via WooCommerce email system
		$subject = 'Your $' . number_format( $amount, 2 ) . ' Coupon';

		// Build HTML message
		$blogname = get_option( 'blogname' );
		$message = '<html><body>';
		$message .= '<h2>You\'ve Received a Coupon!</h2>';
		$message .= '<p>Hi,</p>';
		$message .= '<p>You\'ve been given a <strong>$' . number_format( $amount, 2 ) . ' discount coupon</strong> from ' . esc_html( $blogname ) . '!</p>';
		$message .= '<h3 style="color: #0073aa;">Your Coupon Code</h3>';
		$message .= '<div style="background: #f5f5f5; padding: 15px; border-left: 4px solid #0073aa; border-radius: 4px;">';
		$message .= '<p style="font-size: 18px; font-weight: bold; color: #0073aa; letter-spacing: 2px;">' . esc_html( $code ) . '</p>';
		$message .= '</div>';
		$message .= '<h3>Coupon Details</h3>';
		$message .= '<ul>';
		$message .= '<li><strong>Discount:</strong> $' . number_format( $amount, 2 ) . '</li>';
		$message .= '<li><strong>Valid Until:</strong> ' . date( 'Y-m-d', strtotime( "+$days days" ) ) . '</li>';
		$message .= '<li><strong>Usage:</strong> Once per customer</li>';
		$message .= '</ul>';
		$message .= '<p>Use this coupon code at checkout on your next purchase!</p>';
		$message .= '<p>Best regards,<br>' . esc_html( $blogname ) . '</p>';
		$message .= '</body></html>';

		// Send via WooCommerce email system
		if ( class_exists( 'WC_Email' ) ) {
			error_log( "WC Loyalty Coupon: Attempting to send email to $recipient for order $order_id via WooCommerce" );

			// Get admin email for From header
			$admin_email = get_option( 'admin_email' );
			$headers = array(
				'Content-Type: text/html; charset=UTF-8',
				'From: ' . get_option( 'blogname' ) . ' <' . $admin_email . '>'
			);

			$sent = wp_mail( $recipient, $subject, $message, $headers );

			if ( $sent ) {
				error_log( "WC Loyalty Coupon: ✓ Email sent successfully to $recipient for order $order_id" );
			} else {
				error_log( "WC Loyalty Coupon: ✗ Email FAILED to send to $recipient for order $order_id. Check your site's email configuration." );
			}
		} else {
			error_log( "WC Loyalty Coupon: WooCommerce email system not available" );
		}

	} catch ( Exception $e ) {
		error_log( 'WC Loyalty Coupon Error: ' . $e->getMessage() );
	}
}

/**
 * Add metabox to order page
 */
function wc_loyalty_add_order_metabox() {
	add_meta_box(
		'wc_loyalty_coupon_info',
		'Loyalty Coupon',
		'wc_loyalty_order_metabox_content',
		'shop_order',
		'normal',
		'high'
	);
}

/**
 * Display metabox content on order page
 */
function wc_loyalty_order_metabox_content( $post ) {
	$order_id = $post->ID;

	// Check if processed
	$processed = get_post_meta( $order_id, '_wc_loyalty_processed', true );
	if ( ! $processed ) {
		echo '<p style="color: #999;">No loyalty coupon created for this order.</p>';
		return;
	}

	// Get choice
	$choice = get_post_meta( $order_id, '_wc_loyalty_choice', true );
	$friend_email = get_post_meta( $order_id, '_wc_loyalty_friend_email', true );

	// Get coupon
	global $wpdb;
	$coupon_id = $wpdb->get_var( $wpdb->prepare(
		"SELECT post_id FROM $wpdb->postmeta WHERE meta_key = '_wc_loyalty_order_id' AND meta_value = %d LIMIT 1",
		$order_id
	) );

	if ( ! $coupon_id ) {
		echo '<p style="color: #999;">Coupon not found.</p>';
		return;
	}

	$coupon = new WC_Coupon( $coupon_id );
	$code = $coupon->get_code();
	$amount = $coupon->get_amount();
	$expires = $coupon->get_date_expires() ? $coupon->get_date_expires()->format( 'Y-m-d' ) : 'Never';
	$used = $coupon->get_usage_count() > 0;

	?>
	<div style="background: #f9f9f9; padding: 15px; border-left: 4px solid #0073aa; border-radius: 4px;">
		<table style="width: 100%;">
			<tr>
				<td style="width: 30%; font-weight: bold;">Coupon Code:</td>
				<td><code style="background: #fff; padding: 5px 10px; border: 1px solid #ddd; border-radius: 3px;"><?php echo esc_html( $code ); ?></code></td>
			</tr>
			<tr>
				<td style="width: 30%; font-weight: bold;">Amount:</td>
				<td>$<?php echo number_format( $amount, 2 ); ?></td>
			</tr>
			<tr>
				<td style="width: 30%; font-weight: bold;">Type:</td>
				<td>
					<?php if ( 'gift' === $choice ) : ?>
						<span style="background: #2271b1; color: white; padding: 3px 8px; border-radius: 3px; font-size: 12px;">🎁 Gift</span>
					<?php else : ?>
						<span style="background: #117722; color: white; padding: 3px 8px; border-radius: 3px; font-size: 12px;">Personal</span>
					<?php endif; ?>
				</td>
			</tr>
			<tr>
				<td style="width: 30%; font-weight: bold;">Recipient:</td>
				<td>
					<?php
					if ( 'gift' === $choice ) {
						echo esc_html( $friend_email );
					} else {
						$order = wc_get_order( $order_id );
						echo esc_html( $order->get_billing_email() );
					}
					?>
				</td>
			</tr>
			<tr>
				<td style="width: 30%; font-weight: bold;">Expires:</td>
				<td><?php echo esc_html( $expires ); ?></td>
			</tr>
			<tr>
				<td style="width: 30%; font-weight: bold;">Status:</td>
				<td>
					<?php if ( $used ) : ?>
						<span style="color: green; font-weight: bold;">✓ Used</span>
					<?php else : ?>
						<span style="color: orange; font-weight: bold;">⏱ Unused</span>
					<?php endif; ?>
				</td>
			</tr>
		</table>
	</div>
	<?php
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

	$tab = isset( $_GET['tab'] ) ? sanitize_text_field( $_GET['tab'] ) : 'coupons';
	?>
	<div class="wrap">
		<h1>Loyalty Coupons</h1>

		<nav class="nav-tab-wrapper">
			<a href="?page=wc-loyalty-coupon&tab=coupons" class="nav-tab <?php echo $tab === 'coupons' ? 'nav-tab-active' : ''; ?>">Coupons Created</a>
			<a href="?page=wc-loyalty-coupon&tab=settings" class="nav-tab <?php echo $tab === 'settings' ? 'nav-tab-active' : ''; ?>">Settings</a>
		</nav>

		<div style="background: #fff; padding: 20px; border: 1px solid #ccc; margin-top: 20px;">
			<?php if ( $tab === 'settings' ) : ?>
				<h2>Settings</h2>
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
			<?php else : ?>
				<h2>Loyalty Coupons Created</h2>
				<?php wc_loyalty_show_coupons_table(); ?>
			<?php endif; ?>
		</div>
	</div>
	<?php
}

/**
 * Show table of created coupons
 */
function wc_loyalty_show_coupons_table() {
	global $wpdb;

	// Get all loyalty coupons
	$results = $wpdb->get_results( "
		SELECT p.ID, p.post_title, pm.meta_value as order_id
		FROM {$wpdb->posts} p
		JOIN {$wpdb->postmeta} pm ON p.ID = pm.post_id
		WHERE p.post_type = 'shop_coupon'
		AND pm.meta_key = '_wc_loyalty_order_id'
		ORDER BY p.ID DESC
	" );

	if ( empty( $results ) ) {
		echo '<p>No loyalty coupons created yet.</p>';
		return;
	}

	?>
	<table class="wp-list-table widefat">
		<thead>
			<tr>
				<th style="width: 15%;">Coupon Code</th>
				<th style="width: 10%;">Amount</th>
				<th style="width: 15%;">Recipient Email</th>
				<th style="width: 10%;">Order ID</th>
				<th style="width: 12%;">Created</th>
				<th style="width: 12%;">Expires</th>
				<th style="width: 10%;">Status</th>
				<th style="width: 10%;">Type</th>
			</tr>
		</thead>
		<tbody>
			<?php foreach ( $results as $row ) :
				$coupon = new WC_Coupon( $row->ID );
				$order = wc_get_order( $row->order_id );
				$order_id = $row->order_id;

				// Get recipient info
				$gift_choice = get_post_meta( $order_id, '_wc_loyalty_choice', true );
				if ( 'gift' === $gift_choice ) {
					$recipient = get_post_meta( $order_id, '_wc_loyalty_friend_email', true );
					$type = 'Gift';
				} else {
					$recipient = $order ? $order->get_billing_email() : 'N/A';
					$type = 'Personal';
				}

				$amount = $coupon->get_amount();
				$used = $coupon->get_usage_count() > 0;
				$expires = $coupon->get_date_expires() ? $coupon->get_date_expires()->format( 'Y-m-d' ) : 'Never';
				$created = get_the_time( 'Y-m-d H:i', $row->ID );
				?>
				<tr>
					<td><strong><?php echo esc_html( $coupon->get_code() ); ?></strong></td>
					<td>$<?php echo number_format( $amount, 2 ); ?></td>
					<td><?php echo esc_html( $recipient ); ?></td>
					<td><a href="<?php echo admin_url( 'post.php?post=' . $order_id . '&action=edit' ); ?>"><?php echo $order_id; ?></a></td>
					<td><?php echo $created; ?></td>
					<td><?php echo $expires; ?></td>
					<td>
						<?php if ( $used ) : ?>
							<span style="color: green; font-weight: bold;">✓ Used</span>
						<?php else : ?>
							<span style="color: orange; font-weight: bold;">⏱ Unused</span>
						<?php endif; ?>
					</td>
					<td><?php echo $type; ?></td>
				</tr>
			<?php endforeach; ?>
		</tbody>
	</table>

	<div style="margin-top: 20px; padding: 10px; background: #f5f5f5; border-left: 4px solid #0073aa;">
		<p><strong>Total Coupons:</strong> <?php echo count( $results ); ?></p>
		<p><strong>Used:</strong> <?php echo count( array_filter( $results, function( $r ) { $c = new WC_Coupon( $r->ID ); return $c->get_usage_count() > 0; } ) ); ?></p>
		<p><strong>Unused:</strong> <?php echo count( array_filter( $results, function( $r ) { $c = new WC_Coupon( $r->ID ); return $c->get_usage_count() === 0; } ) ); ?></p>
	</div>
	<?php
}
