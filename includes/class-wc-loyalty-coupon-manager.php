<?php
/**
 * WC Loyalty Coupon Manager
 *
 * Handles coupon creation and management logic
 */

if ( ! defined( 'ABSPATH' ) ) {
	exit;
}

class WC_Loyalty_Coupon_Manager {

	/**
	 * Initialize hooks
	 */
	public static function init() {
		add_action( 'woocommerce_thankyou', array( __CLASS__, 'maybe_create_coupon' ) );
		add_action( 'woocommerce_order_status_completed', array( __CLASS__, 'create_coupon_from_order' ) );
	}

	/**
	 * Create coupon for completed orders
	 *
	 * @param int $order_id Order ID
	 */
	public static function create_coupon_from_order( $order_id ) {
		$order = wc_get_order( $order_id );

		if ( ! $order ) {
			return;
		}

		// Check if coupon already created for this order
		if ( get_post_meta( $order_id, '_loyalty_coupon_created', true ) ) {
			return;
		}

		// Check order total
		$min_amount = (float) get_option( 'wc_loyalty_coupon_min_amount', 250 );
		if ( $order->get_total() < $min_amount ) {
			return;
		}

		// Create coupon
		self::create_coupon( $order );

		// Mark as processed
		update_post_meta( $order_id, '_loyalty_coupon_created', time() );
	}

	/**
	 * Maybe create coupon on thankyou page
	 *
	 * @param int $order_id Order ID
	 */
	public static function maybe_create_coupon( $order_id ) {
		$order = wc_get_order( $order_id );

		if ( ! $order || 'completed' === $order->get_status() ) {
			return;
		}

		// For immediate processing on thankyou page
		$min_amount = (float) get_option( 'wc_loyalty_coupon_min_amount', 250 );
		if ( $order->get_total() >= $min_amount && ! get_post_meta( $order_id, '_loyalty_coupon_created', true ) ) {
			self::create_coupon( $order );
			update_post_meta( $order_id, '_loyalty_coupon_created', time() );
		}
	}

	/**
	 * Create loyalty coupon for customer
	 *
	 * @param WC_Order $order Order object
	 * @return bool|int Coupon ID or false on failure
	 */
	public static function create_coupon( $order ) {
		$coupon_amount = (float) get_option( 'wc_loyalty_coupon_amount', 35 );
		$days_valid = (int) get_option( 'wc_loyalty_coupon_days_valid', 30 );
		$customer = $order->get_user();
		$customer_email = $order->get_billing_email();

		if ( ! $customer && ! $customer_email ) {
			return false;
		}

		// Generate unique coupon code
		$coupon_code = self::generate_coupon_code( $order->get_id() );

		// Check if coupon code already exists
		if ( wc_get_coupon_id_by_code( $coupon_code ) ) {
			return false;
		}

		// Create coupon post
		$coupon_post = array(
			'post_title'  => $coupon_code,
			'post_type'   => 'shop_coupon',
			'post_status' => 'publish',
		);

		$coupon_id = wp_insert_post( $coupon_post );

		if ( ! $coupon_id || is_wp_error( $coupon_id ) ) {
			return false;
		}

		// Get coupon object
		$coupon = new WC_Coupon( $coupon_id );

		// Set coupon properties
		$coupon->set_code( $coupon_code );
		$coupon->set_discount_type( 'fixed_cart' );
		$coupon->set_amount( $coupon_amount );
		$coupon->set_usage_limit( 1 );
		$coupon->set_usage_limit_per_user( 1 );

		// Set expiry date
		$expiry_date = wp_date( 'Y-m-d', strtotime( "+{$days_valid} days" ) );
		$coupon->set_date_expires( $expiry_date );

		// Set individual use
		$coupon->set_individual_use( true );

		// Add customer email restriction
		if ( $customer_email ) {
			$coupon->set_email_restrictions( array( $customer_email ) );
		}

		// Save coupon
		$coupon->save();

		// Add metadata
		update_post_meta( $coupon_id, '_loyalty_coupon_order_id', $order->get_id() );
		update_post_meta( $coupon_id, '_loyalty_coupon_customer_id', $customer ? $customer->ID : 0 );
		update_post_meta( $coupon_id, '_loyalty_coupon_created_date', current_time( 'mysql' ) );

		return $coupon_id;
	}

	/**
	 * Generate unique coupon code
	 *
	 * @param int $order_id Order ID
	 * @return string Coupon code
	 */
	private static function generate_coupon_code( $order_id ) {
		$code = 'LOYALTY-' . $order_id . '-' . strtoupper( substr( md5( wp_rand() ), 0, 6 ) );
		return sanitize_text_field( $code );
	}

	/**
	 * Get all loyalty coupons
	 *
	 * @param array $args Query arguments
	 * @return array Array of coupon data
	 */
	public static function get_loyalty_coupons( $args = array() ) {
		$defaults = array(
			'post_type'      => 'shop_coupon',
			'posts_per_page' => -1,
			'orderby'        => 'ID',
			'order'          => 'DESC',
		);

		$args = wp_parse_args( $args, $defaults );

		$query = new WP_Query( $args );
		$coupons = array();

		foreach ( $query->posts as $post ) {
			$coupon = new WC_Coupon( $post->ID );

			// Only return loyalty coupons
			if ( get_post_meta( $post->ID, '_loyalty_coupon_order_id', true ) ) {
				$coupons[] = array(
					'id'              => $post->ID,
					'code'            => $coupon->get_code(),
					'amount'          => $coupon->get_amount(),
					'order_id'        => get_post_meta( $post->ID, '_loyalty_coupon_order_id', true ),
					'customer_id'     => get_post_meta( $post->ID, '_loyalty_coupon_customer_id', true ),
					'created_date'    => get_post_meta( $post->ID, '_loyalty_coupon_created_date', true ),
					'expiry_date'     => $coupon->get_date_expires() ? $coupon->get_date_expires()->format( 'Y-m-d' ) : 'Never',
					'usage_count'     => $coupon->get_usage_count(),
					'status'          => 'used' === $coupon->get_status() ? 'Used' : 'Unused',
				);
			}
		}

		return $coupons;
	}

	/**
	 * Delete loyalty coupon
	 *
	 * @param int $coupon_id Coupon ID
	 * @return bool Success
	 */
	public static function delete_coupon( $coupon_id ) {
		if ( ! get_post_meta( $coupon_id, '_loyalty_coupon_order_id', true ) ) {
			return false;
		}

		return wp_delete_post( $coupon_id, true );
	}

	/**
	 * Manually create coupon for customer
	 *
	 * @param int $user_id User/Customer ID
	 * @return bool|int Coupon ID or false
	 */
	public static function create_manual_coupon( $user_id ) {
		$customer = new WC_Customer( $user_id );

		if ( ! $customer || ! $customer->get_email() ) {
			return false;
		}

		// Create a temporary order object for coupon creation
		$temp_order = new stdClass();
		$temp_order->ID = $user_id;

		// Create coupon using existing logic
		$coupon_amount = (float) get_option( 'wc_loyalty_coupon_amount', 35 );
		$days_valid = (int) get_option( 'wc_loyalty_coupon_days_valid', 30 );

		$coupon_code = 'MANUAL-' . $user_id . '-' . strtoupper( substr( md5( wp_rand() ), 0, 6 ) );

		// Check if coupon code already exists
		if ( wc_get_coupon_id_by_code( $coupon_code ) ) {
			return false;
		}

		// Create coupon post
		$coupon_post = array(
			'post_title'  => $coupon_code,
			'post_type'   => 'shop_coupon',
			'post_status' => 'publish',
		);

		$coupon_id = wp_insert_post( $coupon_post );

		if ( ! $coupon_id || is_wp_error( $coupon_id ) ) {
			return false;
		}

		// Get coupon object
		$coupon = new WC_Coupon( $coupon_id );

		// Set coupon properties
		$coupon->set_code( $coupon_code );
		$coupon->set_discount_type( 'fixed_cart' );
		$coupon->set_amount( $coupon_amount );
		$coupon->set_usage_limit( 1 );
		$coupon->set_usage_limit_per_user( 1 );

		// Set expiry date
		$expiry_date = wp_date( 'Y-m-d', strtotime( "+{$days_valid} days" ) );
		$coupon->set_date_expires( $expiry_date );

		// Set individual use
		$coupon->set_individual_use( true );

		// Add customer email restriction
		$coupon->set_email_restrictions( array( $customer->get_email() ) );

		// Save coupon
		$coupon->save();

		// Add metadata
		update_post_meta( $coupon_id, '_loyalty_coupon_order_id', 0 );
		update_post_meta( $coupon_id, '_loyalty_coupon_customer_id', $user_id );
		update_post_meta( $coupon_id, '_loyalty_coupon_created_date', current_time( 'mysql' ) );
		update_post_meta( $coupon_id, '_loyalty_coupon_manual', 1 );

		return $coupon_id;
	}
}
