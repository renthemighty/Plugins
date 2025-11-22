<?php
/**
 * WooCommerce Loyalty Coupon Email - Gift
 */

if ( ! defined( 'ABSPATH' ) ) {
	exit;
}

if ( ! class_exists( 'WC_Loyalty_Coupon_Email_Gift' ) ) {
	class WC_Loyalty_Coupon_Email_Gift extends WC_Email {

		public $coupon;
		public $recipient_email;

		public function __construct() {
			$this->id             = 'wc_loyalty_coupon_gift';
			$this->title          = 'Loyalty Coupon - Gift';
			$this->description    = 'Sent when a customer gifts a loyalty coupon to a friend';
			$this->subject        = 'You\'ve Been Gifted a Coupon!';
			$this->heading        = 'You\'ve Been Gifted a Coupon!';
			$this->customer_email = false;

			parent::__construct();
		}

		public function trigger( $order_id, $coupon, $recipient_email ) {
			$this->object          = wc_get_order( $order_id );
			$this->coupon          = $coupon;
			$this->recipient_email = $recipient_email;

			if ( ! $this->is_enabled() || ! $this->get_recipient() ) {
				return;
			}

			$this->send( $this->get_recipient(), $this->get_subject(), $this->get_content(), $this->get_headers(), $this->get_attachments() );
		}

		public function get_recipient() {
			return $this->recipient_email;
		}

		public function get_subject() {
			$amount = $this->coupon ? number_format( $this->coupon->get_amount(), 2 ) : '0.00';
			return apply_filters( 'woocommerce_email_subject_' . $this->id, "You've Been Gifted a \$$amount Coupon!", $this->object );
		}

		public function get_heading() {
			return apply_filters( 'woocommerce_email_heading_' . $this->id, 'You\'ve Been Gifted a Coupon!', $this->object );
		}

		public function get_content_html() {
			if ( ! $this->coupon || ! $this->coupon->get_code() ) {
				return '<p>Error: Coupon not found.</p>';
			}

			$coupon_code = esc_html( $this->coupon->get_code() );
			$amount = number_format( $this->coupon->get_amount(), 2 );
			$expires = $this->coupon->get_date_expires() ? $this->coupon->get_date_expires()->format( get_option( 'date_format' ) ) : 'Never';
			$blogname = esc_html( get_option( 'blogname' ) );

			$html = '<h2>Great news!</h2>' . "\n\n";
			$html .= '<p>A friend has gifted you a <strong>$' . $amount . ' coupon</strong> from ' . $blogname . '!</p>' . "\n\n";
			$html .= '<p style="color: #666; font-size: 14px;">That\'s what we call friendship! Your friend thought of you and wanted to share the savings.</p>' . "\n\n";
			$html .= '<h3 style="color: #28a745; margin-top: 20px;">Your Coupon Code</h3>' . "\n";
			$html .= '<div style="background: #f5f5f5; padding: 15px; border-left: 4px solid #28a745; border-radius: 4px; margin: 20px 0;">' . "\n";
			$html .= '<p style="font-size: 18px; font-weight: bold; color: #28a745; margin: 0; letter-spacing: 2px;">' . $coupon_code . '</p>' . "\n";
			$html .= '</div>' . "\n\n";
			$html .= '<h3>Coupon Details</h3>' . "\n";
			$html .= '<ul style="list-style: none; padding: 0;">' . "\n";
			$html .= '<li style="padding: 5px 0;"><strong>Discount:</strong> $' . $amount . '</li>' . "\n";
			$html .= '<li style="padding: 5px 0;"><strong>Valid Until:</strong> ' . esc_html( $expires ) . '</li>' . "\n";
			$html .= '<li style="padding: 5px 0;"><strong>Usage:</strong> Once per customer</li>' . "\n";
			$html .= '</ul>' . "\n\n";
			$html .= '<p>Ready to use your gift? Simply apply this coupon code at checkout on your next purchase at ' . $blogname . '!</p>' . "\n\n";
			$html .= '<p>Happy shopping!</p>' . "\n";

			return $html;
		}

		public function get_content_plain() {
			if ( ! $this->coupon || ! $this->coupon->get_code() ) {
				return 'Error: Coupon not found.';
			}

			$coupon_code = $this->coupon->get_code();
			$amount = number_format( $this->coupon->get_amount(), 2 );
			$expires = $this->coupon->get_date_expires() ? $this->coupon->get_date_expires()->format( get_option( 'date_format' ) ) : 'Never';
			$blogname = get_option( 'blogname' );

			$text = "Great news!\n\n";
			$text .= "A friend has gifted you a \$$amount coupon from $blogname!\n\n";
			$text .= "That's what we call friendship! Your friend thought of you and wanted to share the savings.\n\n";
			$text .= "YOUR COUPON CODE:\n";
			$text .= "$coupon_code\n\n";
			$text .= "COUPON DETAILS:\n";
			$text .= "Discount: \$$amount\n";
			$text .= "Valid Until: $expires\n";
			$text .= "Usage: Once per customer\n\n";
			$text .= "Ready to use your gift? Simply apply this coupon code at checkout on your next purchase at $blogname!\n\n";
			$text .= "Happy shopping!";

			return $text;
		}
	}
}
