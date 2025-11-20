<?php
/**
 * WC Loyalty Coupon Admin
 *
 * Handles admin dashboard and settings
 */

if ( ! defined( 'ABSPATH' ) ) {
	exit;
}

class WC_Loyalty_Coupon_Admin {

	/**
	 * Initialize admin hooks
	 */
	public static function init() {
		add_action( 'admin_menu', array( __CLASS__, 'add_admin_menu' ) );
		add_action( 'admin_init', array( __CLASS__, 'register_settings' ) );
		add_action( 'admin_post_wc_loyalty_coupon_delete', array( __CLASS__, 'handle_delete_coupon' ) );
		add_action( 'admin_post_wc_loyalty_coupon_create', array( __CLASS__, 'handle_create_coupon' ) );
	}

	/**
	 * Add admin menu
	 */
	public static function add_admin_menu() {
		add_submenu_page(
			'woocommerce',
			'Loyalty Coupons',
			'Loyalty Coupons',
			'manage_woocommerce',
			'wc-loyalty-coupon',
			array( __CLASS__, 'render_admin_page' )
		);
	}

	/**
	 * Register settings
	 */
	public static function register_settings() {
		register_setting(
			'wc_loyalty_coupon_settings',
			'wc_loyalty_coupon_amount',
			array(
				'sanitize_callback' => array( __CLASS__, 'sanitize_amount' ),
				'default'           => 35,
			)
		);

		register_setting(
			'wc_loyalty_coupon_settings',
			'wc_loyalty_coupon_min_amount',
			array(
				'sanitize_callback' => array( __CLASS__, 'sanitize_amount' ),
				'default'           => 250,
			)
		);

		register_setting(
			'wc_loyalty_coupon_settings',
			'wc_loyalty_coupon_days_valid',
			array(
				'sanitize_callback' => array( __CLASS__, 'sanitize_days' ),
				'default'           => 30,
			)
		);

		add_settings_section(
			'wc_loyalty_coupon_main',
			'Loyalty Coupon Settings',
			array( __CLASS__, 'render_settings_section' ),
			'wc_loyalty_coupon_settings'
		);

		add_settings_field(
			'wc_loyalty_coupon_amount',
			'Coupon Discount Amount ($)',
			array( __CLASS__, 'render_amount_field' ),
			'wc_loyalty_coupon_settings',
			'wc_loyalty_coupon_main'
		);

		add_settings_field(
			'wc_loyalty_coupon_min_amount',
			'Minimum Order Amount ($)',
			array( __CLASS__, 'render_min_amount_field' ),
			'wc_loyalty_coupon_settings',
			'wc_loyalty_coupon_main'
		);

		add_settings_field(
			'wc_loyalty_coupon_days_valid',
			'Coupon Valid Days',
			array( __CLASS__, 'render_days_field' ),
			'wc_loyalty_coupon_settings',
			'wc_loyalty_coupon_main'
		);
	}

	/**
	 * Sanitize amount field
	 */
	public static function sanitize_amount( $value ) {
		return max( 0, floatval( $value ) );
	}

	/**
	 * Sanitize days field
	 */
	public static function sanitize_days( $value ) {
		return max( 1, intval( $value ) );
	}

	/**
	 * Render settings section
	 */
	public static function render_settings_section() {
		echo '<p>Configure automatic loyalty coupon settings.</p>';
	}

	/**
	 * Render amount field
	 */
	public static function render_amount_field() {
		$value = get_option( 'wc_loyalty_coupon_amount', 35 );
		echo '<input type="number" step="0.01" name="wc_loyalty_coupon_amount" value="' . esc_attr( $value ) . '" />';
	}

	/**
	 * Render minimum amount field
	 */
	public static function render_min_amount_field() {
		$value = get_option( 'wc_loyalty_coupon_min_amount', 250 );
		echo '<input type="number" step="0.01" name="wc_loyalty_coupon_min_amount" value="' . esc_attr( $value ) . '" />';
	}

	/**
	 * Render days field
	 */
	public static function render_days_field() {
		$value = get_option( 'wc_loyalty_coupon_days_valid', 30 );
		echo '<input type="number" name="wc_loyalty_coupon_days_valid" value="' . esc_attr( $value ) . '" min="1" />';
	}

	/**
	 * Render admin page
	 */
	public static function render_admin_page() {
		if ( ! current_user_can( 'manage_woocommerce' ) ) {
			wp_die( 'Unauthorized' );
		}

		// Get current tab
		$tab = isset( $_GET['tab'] ) ? sanitize_text_field( wp_unslash( $_GET['tab'] ) ) : 'dashboard';

		?>
		<div class="wrap wc-loyalty-coupon-wrap">
			<h1>WooCommerce Loyalty Coupons</h1>

			<nav class="nav-tab-wrapper">
				<a href="?page=wc-loyalty-coupon&tab=dashboard" class="nav-tab <?php echo 'dashboard' === $tab ? 'nav-tab-active' : ''; ?>">Dashboard</a>
				<a href="?page=wc-loyalty-coupon&tab=coupons" class="nav-tab <?php echo 'coupons' === $tab ? 'nav-tab-active' : ''; ?>">Coupons</a>
				<a href="?page=wc-loyalty-coupon&tab=settings" class="nav-tab <?php echo 'settings' === $tab ? 'nav-tab-active' : ''; ?>">Settings</a>
			</nav>

			<div class="tab-content">
				<?php
				switch ( $tab ) {
					case 'coupons':
						self::render_coupons_page();
						break;
					case 'settings':
						self::render_settings_page();
						break;
					default:
						self::render_dashboard_page();
				}
				?>
			</div>
		</div>

		<style>
			.wc-loyalty-coupon-wrap {
				background: #fff;
				padding: 20px;
				border-radius: 4px;
			}
			.wc-loyalty-coupon-wrap table {
				width: 100%;
				border-collapse: collapse;
				margin-top: 20px;
			}
			.wc-loyalty-coupon-wrap table th,
			.wc-loyalty-coupon-wrap table td {
				padding: 12px;
				border-bottom: 1px solid #ddd;
				text-align: left;
			}
			.wc-loyalty-coupon-wrap table th {
				background: #f5f5f5;
				font-weight: bold;
			}
			.wc-loyalty-coupon-wrap table tr:hover {
				background: #f9f9f9;
			}
			.wc-loyalty-coupon-wrap .stats-grid {
				display: grid;
				grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
				gap: 20px;
				margin: 20px 0;
			}
			.wc-loyalty-coupon-wrap .stat-box {
				background: #f5f5f5;
				padding: 20px;
				border-radius: 4px;
				border-left: 4px solid #0073aa;
			}
			.wc-loyalty-coupon-wrap .stat-box h3 {
				margin: 0 0 10px;
				color: #0073aa;
				font-size: 14px;
				text-transform: uppercase;
			}
			.wc-loyalty-coupon-wrap .stat-box .value {
				font-size: 32px;
				font-weight: bold;
				color: #333;
			}
			.wc-loyalty-coupon-wrap .button {
				margin-right: 10px;
			}
			.wc-loyalty-coupon-wrap .delete-btn {
				color: #a00;
			}
			.wc-loyalty-coupon-wrap .delete-btn:hover {
				color: #dc3545;
			}
			.wc-loyalty-coupon-wrap form {
				max-width: 500px;
				background: #f9f9f9;
				padding: 20px;
				border-radius: 4px;
				border: 1px solid #ddd;
			}
			.wc-loyalty-coupon-wrap .form-group {
				margin-bottom: 20px;
			}
			.wc-loyalty-coupon-wrap label {
				display: block;
				margin-bottom: 8px;
				font-weight: bold;
				color: #333;
			}
			.wc-loyalty-coupon-wrap input[type="number"],
			.wc-loyalty-coupon-wrap select {
				width: 100%;
				padding: 8px 12px;
				border: 1px solid #ddd;
				border-radius: 4px;
				box-sizing: border-box;
			}
			.wc-loyalty-coupon-wrap input[type="number"]:focus,
			.wc-loyalty-coupon-wrap select:focus {
				outline: none;
				border-color: #0073aa;
				box-shadow: 0 0 0 2px rgba(0, 115, 170, 0.1);
			}
		</style>
		<?php
	}

	/**
	 * Render dashboard page
	 */
	private static function render_dashboard_page() {
		$coupons = WC_Loyalty_Coupon_Manager::get_loyalty_coupons();
		$used_count = 0;
		$total_value = 0;
		$coupon_amount = (float) get_option( 'wc_loyalty_coupon_amount', 35 );

		foreach ( $coupons as $coupon ) {
			$total_value += $coupon['amount'];
			if ( 'Used' === $coupon['status'] ) {
				$used_count++;
			}
		}

		?>
		<div class="stats-grid">
			<div class="stat-box">
				<h3>Total Coupons</h3>
				<div class="value"><?php echo count( $coupons ); ?></div>
			</div>
			<div class="stat-box">
				<h3>Used Coupons</h3>
				<div class="value"><?php echo $used_count; ?></div>
			</div>
			<div class="stat-box">
				<h3>Unused Coupons</h3>
				<div class="value"><?php echo count( $coupons ) - $used_count; ?></div>
			</div>
			<div class="stat-box">
				<h3>Total Value</h3>
				<div class="value">$<?php echo number_format( $total_value, 2 ); ?></div>
			</div>
		</div>

		<h2>Recent Coupons</h2>
		<?php
		if ( empty( $coupons ) ) {
			echo '<p>No loyalty coupons generated yet.</p>';
		} else {
			self::render_coupons_table( array_slice( $coupons, 0, 10 ) );
		}
	}

	/**
	 * Render coupons page
	 */
	private static function render_coupons_page() {
		$coupons = WC_Loyalty_Coupon_Manager::get_loyalty_coupons();

		?>
		<h2>All Loyalty Coupons</h2>

		<div style="margin: 20px 0;">
			<button class="button button-primary" id="create-manual-coupon-btn">Create Manual Coupon</button>
		</div>

		<?php
		if ( empty( $coupons ) ) {
			echo '<p>No loyalty coupons generated yet.</p>';
		} else {
			self::render_coupons_table( $coupons );
		}
	}

	/**
	 * Render coupons table
	 */
	private static function render_coupons_table( $coupons ) {
		?>
		<table>
			<thead>
				<tr>
					<th>Coupon Code</th>
					<th>Amount</th>
					<th>Customer</th>
					<th>Created Date</th>
					<th>Expires</th>
					<th>Status</th>
					<th>Actions</th>
				</tr>
			</thead>
			<tbody>
				<?php
				foreach ( $coupons as $coupon ) {
					$customer = '';
					if ( $coupon['customer_id'] ) {
						$customer_obj = new WC_Customer( $coupon['customer_id'] );
						$customer = $customer_obj->get_first_name() . ' ' . $customer_obj->get_last_name();
					}

					$delete_url = add_query_arg(
						array(
							'action'      => 'wc_loyalty_coupon_delete',
							'coupon_id'   => $coupon['id'],
							'_wpnonce'    => wp_create_nonce( 'delete_loyalty_coupon_' . $coupon['id'] ),
						),
						admin_url( 'admin-post.php' )
					);

					$status_class = 'Used' === $coupon['status'] ? 'used' : 'unused';
					?>
					<tr>
						<td><strong><?php echo esc_html( $coupon['code'] ); ?></strong></td>
						<td>$<?php echo number_format( $coupon['amount'], 2 ); ?></td>
						<td><?php echo esc_html( $customer ); ?></td>
						<td><?php echo esc_html( $coupon['created_date'] ); ?></td>
						<td><?php echo esc_html( $coupon['expiry_date'] ); ?></td>
						<td><span class="<?php echo esc_attr( $status_class ); ?>"><?php echo esc_html( $coupon['status'] ); ?></span></td>
						<td>
							<a href="<?php echo esc_url( $delete_url ); ?>" class="button button-small delete-btn" onclick="return confirm('Delete this coupon?');">Delete</a>
						</td>
					</tr>
					<?php
				}
				?>
			</tbody>
		</table>
		<?php
	}

	/**
	 * Render settings page
	 */
	private static function render_settings_page() {
		?>
		<h2>Settings</h2>
		<form method="post" action="options.php">
			<?php settings_fields( 'wc_loyalty_coupon_settings' ); ?>
			<?php do_settings_sections( 'wc_loyalty_coupon_settings' ); ?>
			<?php submit_button(); ?>
		</form>
		<?php
	}

	/**
	 * Handle delete coupon
	 */
	public static function handle_delete_coupon() {
		if ( ! isset( $_GET['_wpnonce'] ) ) {
			wp_die( 'Nonce verification failed' );
		}

		$coupon_id = isset( $_GET['coupon_id'] ) ? intval( $_GET['coupon_id'] ) : 0;
		$nonce = sanitize_text_field( wp_unslash( $_GET['_wpnonce'] ) );

		if ( ! wp_verify_nonce( $nonce, 'delete_loyalty_coupon_' . $coupon_id ) ) {
			wp_die( 'Nonce verification failed' );
		}

		if ( ! current_user_can( 'manage_woocommerce' ) ) {
			wp_die( 'Unauthorized' );
		}

		if ( WC_Loyalty_Coupon_Manager::delete_coupon( $coupon_id ) ) {
			wp_safe_remote_post(
				admin_url( 'admin.php' ),
				array(
					'blocking'  => false,
					'sslverify' => apply_filters( 'https_local_ssl_verify', false ),
				)
			);

			wp_redirect(
				add_query_arg(
					array( 'page' => 'wc-loyalty-coupon', 'tab' => 'coupons' ),
					admin_url( 'admin.php' )
				)
			);
			exit;
		}
	}

	/**
	 * Handle create coupon
	 */
	public static function handle_create_coupon() {
		if ( ! isset( $_POST['_wpnonce'] ) ) {
			wp_die( 'Nonce verification failed' );
		}

		$nonce = sanitize_text_field( wp_unslash( $_POST['_wpnonce'] ) );

		if ( ! wp_verify_nonce( $nonce, 'create_loyalty_coupon' ) ) {
			wp_die( 'Nonce verification failed' );
		}

		if ( ! current_user_can( 'manage_woocommerce' ) ) {
			wp_die( 'Unauthorized' );
		}

		$user_id = isset( $_POST['user_id'] ) ? intval( $_POST['user_id'] ) : 0;

		if ( $user_id ) {
			WC_Loyalty_Coupon_Manager::create_manual_coupon( $user_id );
			wp_redirect(
				add_query_arg(
					array( 'page' => 'wc-loyalty-coupon', 'tab' => 'coupons' ),
					admin_url( 'admin.php' )
				)
			);
			exit;
		}
	}
}
