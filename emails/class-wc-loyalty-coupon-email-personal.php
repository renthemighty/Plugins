<?php
/**
 * WooCommerce Loyalty Coupon Email - Personal
 */

if ( ! defined( 'ABSPATH' ) ) {
	exit;
}

class WC_Loyalty_Coupon_Email_Personal extends WC_Email {

	/**
	 * Constructor
	 */
	public function __construct() {
		$this->id             = 'wc_loyalty_coupon_personal';
		$this->title          = 'Loyalty Coupon - Personal';
		$this->description    = 'Sent when a customer receives a personal loyalty coupon';
		$this->subject        = 'Your {site_title} Loyalty Coupon - ${coupon_amount}';
		$this->heading        = 'Your Loyalty Coupon';
		$this->template_base  = plugin_dir_path( __FILE__ ) . 'templates/';
		$this->template_html  = 'email-loyalty-coupon-personal.php';
		$this->template_plain = 'email-loyalty-coupon-personal-plain.txt';
		$this->placeholders   = array(
			'{site_title}'    => $this->get_blogname(),
			'{coupon_amount}' => '',
		);

		parent::__construct();
	}

	/**
	 * Trigger email
	 */
	public function trigger( $order_id, $coupon, $recipient_email ) {
		if ( ! $order_id || ! $coupon ) {
			return;
		}

		$order = wc_get_order( $order_id );
		if ( ! $order ) {
			return;
		}

		$this->object               = $order;
		$this->coupon               = $coupon;
		$this->recipient            = $recipient_email;
		$this->placeholders['{site_title}']    = $this->get_blogname();
		$this->placeholders['{coupon_amount}'] = wc_price( $coupon->get_amount() );

		$this->subject = sprintf( 'Your %s Loyalty Coupon - $%s', $this->get_blogname(), number_format( $coupon->get_amount(), 2 ) );
		$this->heading = 'Your Loyalty Coupon';

		if ( $this->is_enabled() && $recipient_email ) {
			$this->send( $recipient_email, $this->get_subject(), $this->get_content(), $this->get_headers(), $this->get_attachments() );
		}
	}

	/**
	 * Get email subject
	 */
	public function get_subject() {
		return apply_filters( 'woocommerce_email_subject_' . $this->id, $this->subject, $this->object );
	}

	/**
	 * Get email heading
	 */
	public function get_heading() {
		return apply_filters( 'woocommerce_email_heading_' . $this->id, $this->heading, $this->object );
	}

	/**
	 * Get email content HTML
	 */
	public function get_content_html() {
		$order = $this->object;
		$coupon = $this->coupon;
		$email = $this;
		$email_heading = $this->get_heading();

		ob_start();
		include plugin_dir_path( __FILE__ ) . 'templates/email-loyalty-coupon-personal.php';
		return ob_get_clean();
	}

	/**
	 * Get email content plain text
	 */
	public function get_content_plain() {
		$order = $this->object;
		$coupon = $this->coupon;
		$email = $this;
		$email_heading = $this->get_heading();

		ob_start();
		include plugin_dir_path( __FILE__ ) . 'templates/email-loyalty-coupon-personal-plain.txt';
		return ob_get_clean();
	}

	/**
	 * Get email subject
	 */
	public function get_default_subject() {
		return __( 'Your {site_title} Loyalty Coupon', 'wc-loyalty-coupon' );
	}

	/**
	 * Get email heading
	 */
	public function get_default_heading() {
		return __( 'Your Loyalty Coupon', 'wc-loyalty-coupon' );
	}
}
