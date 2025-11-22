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

	// Hook into order completion
	add_action( 'woocommerce_order_status_completed', 'wc_loyalty_coupon_create_coupon' );

	// Admin hooks
	if ( is_admin() ) {
		add_action( 'admin_menu', 'wc_loyalty_coupon_add_menu' );
		add_action( 'admin_init', 'wc_loyalty_coupon_register_settings' );
		add_action( 'admin_post_wc_loyalty_delete', 'wc_loyalty_coupon_delete_coupon' );
	}
}, 20 );

/**
 * Create loyalty coupon on order completion
 */
function wc_loyalty_coupon_create_coupon( $order_id ) {
	$order = wc_get_order( $order_id );

	if ( ! $order ) {
		return;
	}

	// Skip if already processed
	if ( get_post_meta( $order_id, '_loyalty_coupon_created', true ) ) {
		return;
	}

	$min_amount = (float) get_option( 'wc_loyalty_coupon_min_amount', 250 );

	if ( $order->get_total() < $min_amount ) {
		update_post_meta( $order_id, '_loyalty_coupon_created', 'no_match' );
		return;
	}

	$coupon_amount = (float) get_option( 'wc_loyalty_coupon_amount', 35 );
	$days_valid = (int) get_option( 'wc_loyalty_coupon_days_valid', 30 );
	$customer_email = $order->get_billing_email();

	if ( ! $customer_email ) {
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
	$coupon->set_email_restrictions( array( $customer_email ) );

	$expiry = strtotime( "+{$days_valid} days" );
	$coupon->set_date_expires( $expiry );

	$result = $coupon->save();

	if ( $result ) {
		update_post_meta( $order_id, '_loyalty_coupon_created', current_time( 'mysql' ) );
		update_post_meta( $coupon->get_id(), '_loyalty_order_id', $order_id );
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
				?>
				<tr>
					<td><strong><?php echo esc_html( $coupon['code'] ); ?></strong></td>
					<td>$<?php echo number_format( $coupon['amount'], 2 ); ?></td>
					<td><?php echo esc_html( $coupon['created'] ); ?></td>
					<td><?php echo esc_html( $coupon['expires'] ); ?></td>
					<td><?php echo $coupon['used'] ? '<span style="color: green;">Used</span>' : '<span style="color: orange;">Unused</span>'; ?></td>
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
		if ( ! get_post_meta( $post->ID, '_loyalty_order_id', true ) && ! get_post_meta( $post->ID, '_loyalty_coupon_created', true ) ) {
			continue;
		}

		$coupon = new WC_Coupon( $post->ID );

		$results[] = array(
			'id'      => $post->ID,
			'code'    => $coupon->get_code(),
			'amount'  => $coupon->get_amount(),
			'created' => get_the_time( 'Y-m-d H:i', $post->ID ),
			'expires' => $coupon->get_date_expires() ? $coupon->get_date_expires()->format( 'Y-m-d' ) : 'Never',
			'used'    => $coupon->get_usage_count() > 0,
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
