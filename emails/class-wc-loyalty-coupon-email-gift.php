<?php
/**
 * WooCommerce Loyalty Coupon Email - Gift
 */

if ( ! defined( 'ABSPATH' ) ) {
	exit;
}

class WC_Loyalty_Coupon_Email_Gift extends WC_Email {

	/**
	 * Constructor
	 */
	public function __construct() {
		$this->id             = 'wc_loyalty_coupon_gift';
		$this->title          = 'Loyalty Coupon - Gift';
		$this->description    = 'Sent when a customer gifts a loyalty coupon to a friend';
		$this->subject        = 'You\'ve Been Gifted a Coupon from {site_title}!';
		$this->heading        = 'You\'ve Been Gifted a Coupon!';
		$this->template_base  = plugin_dir_path( __FILE__ ) . 'templates/';
		$this->template_html  = 'email-loyalty-coupon-gift.php';
		$this->template_plain = 'email-loyalty-coupon-gift-plain.txt';
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

		$this->subject = sprintf( 'You\'ve Been Gifted a $%s Coupon from %s!', number_format( $coupon->get_amount(), 2 ), $this->get_blogname() );
		$this->heading = 'You\'ve Been Gifted a Coupon!';

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
		return wc_get_template_html(
			$this->template_html,
			array(
				'order'         => $this->object,
				'coupon'        => $this->coupon,
				'email_heading' => $this->get_heading(),
				'sent_to_admin' => false,
				'plain_text'    => false,
				'email'         => $this,
			),
			'',
			$this->template_base
		);
	}

	/**
	 * Get email content plain text
	 */
	public function get_content_plain() {
		return wc_get_template_html(
			$this->template_plain,
			array(
				'order'         => $this->object,
				'coupon'        => $this->coupon,
				'email_heading' => $this->get_heading(),
				'sent_to_admin' => false,
				'plain_text'    => true,
				'email'         => $this,
			),
			'',
			$this->template_base
		);
	}

	/**
	 * Get email subject
	 */
	public function get_default_subject() {
		return __( 'You\'ve Been Gifted a Coupon from {site_title}!', 'wc-loyalty-coupon' );
	}

	/**
	 * Get email heading
	 */
	public function get_default_heading() {
		return __( 'You\'ve Been Gifted a Coupon!', 'wc-loyalty-coupon' );
	}
}
