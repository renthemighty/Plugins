<?php
/**
 * Shipping Label Template
 *
 * This template renders the printable shipping label.
 * It opens in a new browser tab and is styled for 4x6 thermal label printing.
 *
 * @var array $data Label data passed from the main plugin.
 */
defined('ABSPATH') || exit;
?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title><?php echo esc_html(sprintf(__('Shipping Label - Order #%s', 'wc-local-shipping-labels'), $data['order_id'])); ?></title>
    <style>
        /* Reset */
        *, *::before, *::after {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }

        body {
            font-family: 'Arial', 'Helvetica Neue', Helvetica, sans-serif;
            background: #f0f0f0;
            padding: 20px;
        }

        /* Label container - 4x6 inch label */
        .label {
            width: 4in;
            height: 6in;
            background: #fff;
            border: 1px solid #000;
            margin: 0 auto;
            padding: 0.15in;
            position: relative;
            overflow: hidden;
            display: flex;
            flex-direction: column;
        }

        /* ---- TOP SECTION: Sender + Weight ---- */
        .label-top {
            display: flex;
            justify-content: space-between;
            align-items: flex-start;
            margin-bottom: 0.12in;
        }

        .sender-block {
            font-size: 7.5pt;
            line-height: 1.35;
            font-weight: normal;
            text-transform: uppercase;
        }

        .sender-block .sender-label {
            font-weight: bold;
            font-size: 7.5pt;
        }

        .weight-block {
            text-align: left;
            border: 1.5px solid #000;
            padding: 4px 8px;
            min-width: 1.3in;
        }

        .weight-block .weight-title {
            font-size: 9pt;
            font-weight: bold;
            text-transform: uppercase;
            letter-spacing: 1px;
        }

        .weight-block .weight-fill {
            height: 0.35in;
            border-bottom: 1px solid #ccc;
            margin-top: 2px;
        }

        /* ---- SHIP TO SECTION ---- */
        .ship-to-section {
            margin-bottom: 0.12in;
            padding-bottom: 0.08in;
        }

        .ship-to-row {
            display: flex;
            align-items: flex-start;
            gap: 6px;
        }

        .ship-to-badge {
            font-size: 8pt;
            font-weight: bold;
            background: #000;
            color: #fff;
            padding: 2px 5px;
            line-height: 1.2;
            white-space: nowrap;
            flex-shrink: 0;
            margin-top: 2px;
        }

        .ship-to-details {
            font-size: 11pt;
            font-weight: bold;
            line-height: 1.4;
            text-transform: uppercase;
            text-decoration: underline;
        }

        .ship-to-details .ship-line {
            display: block;
        }

        /* ---- SEPARATOR ---- */
        .separator {
            border: none;
            border-top: 2px solid #000;
            margin: 0.06in 0;
        }

        /* ---- ORDER CODE SECTION (HI XXXXXX RT1 + MaxiCode + Barcode) ---- */
        .order-code-section {
            display: flex;
            align-items: center;
            gap: 6px;
            margin-bottom: 0.04in;
        }

        .maxicode-placeholder {
            width: 0.7in;
            height: 0.7in;
            flex-shrink: 0;
        }

        /* CSS-based MaxiCode approximation */
        .maxicode-symbol {
            width: 0.7in;
            height: 0.7in;
            position: relative;
            display: flex;
            align-items: center;
            justify-content: center;
        }

        .maxicode-symbol svg {
            width: 100%;
            height: 100%;
        }

        .order-code-right {
            flex: 1;
            text-align: center;
        }

        .hi-code {
            font-size: 20pt;
            font-weight: 900;
            letter-spacing: 2px;
            white-space: nowrap;
            line-height: 1.1;
        }

        .hi-code .rt-suffix {
            font-size: 24pt;
            font-weight: 900;
            color: #000;
        }

        .order-barcode {
            margin-top: 2px;
            text-align: center;
        }

        .order-barcode svg {
            width: 100%;
            max-width: 2.6in;
            height: 0.4in;
        }

        /* ---- NEXT DAY SERVICE SECTION ---- */
        .service-section {
            background: #000;
            color: #fff;
            display: flex;
            justify-content: space-between;
            align-items: center;
            padding: 3px 8px;
            margin: 0.04in 0;
        }

        .service-name {
            font-size: 18pt;
            font-weight: 900;
            text-transform: uppercase;
            letter-spacing: 2px;
        }

        .service-number {
            font-size: 28pt;
            font-weight: 900;
        }

        /* ---- TRACKING SECTION ---- */
        .tracking-section {
            margin: 0.04in 0;
        }

        .tracking-text {
            font-size: 7.5pt;
            font-weight: bold;
            text-transform: uppercase;
            margin-bottom: 2px;
        }

        .tracking-barcode {
            text-align: center;
        }

        .tracking-barcode svg {
            width: 100%;
            height: 0.6in;
        }

        /* ---- ROUTING SECTION ---- */
        .routing-section {
            border-top: 2px solid #000;
            padding-top: 0.04in;
            margin-top: auto;
        }

        .routing-line {
            font-size: 7.5pt;
            font-weight: bold;
            text-transform: uppercase;
            line-height: 1.4;
        }

        /* ---- PRINT STYLES ---- */
        @media print {
            body {
                background: none;
                padding: 0;
                margin: 0;
            }

            .label {
                border: none;
                margin: 0;
                page-break-after: always;
            }

            .no-print {
                display: none !important;
            }

            @page {
                size: 4in 6in;
                margin: 0;
            }
        }

        /* ---- PRINT BUTTON (screen only) ---- */
        .print-controls {
            text-align: center;
            margin: 15px auto;
            max-width: 4in;
        }

        .print-controls button {
            background: #2271b1;
            color: #fff;
            border: none;
            padding: 10px 30px;
            font-size: 14px;
            cursor: pointer;
            border-radius: 4px;
        }

        .print-controls button:hover {
            background: #135e96;
        }
    </style>
    <!-- JsBarcode for barcode generation -->
    <script src="https://cdn.jsdelivr.net/npm/jsbarcode@3.11.6/dist/JsBarcode.all.min.js"></script>
</head>
<body>

<div class="print-controls no-print">
    <button onclick="window.print();"><?php esc_html_e('Print Label', 'wc-local-shipping-labels'); ?></button>
</div>

<div class="label">

    <!-- TOP: Sender + Weight -->
    <div class="label-top">
        <div class="sender-block">
            <span class="sender-label">SENDER:</span><br>
            <?php echo esc_html($data['sender_name']); ?><br>
            <?php if (!empty($data['sender_phone'])) : ?>
                <?php echo esc_html($data['sender_phone']); ?><br>
            <?php endif; ?>
            <?php if (!empty($data['sender_address'])) : ?>
                <?php echo esc_html($data['sender_address']); ?><br>
            <?php endif; ?>
            <?php if (!empty($data['sender_city'])) : ?>
                <?php echo esc_html($data['sender_city']); ?>
            <?php endif; ?>
        </div>
        <div class="weight-block">
            <div class="weight-title">WEIGHT</div>
            <div class="weight-fill"></div>
        </div>
    </div>

    <!-- SHIP TO -->
    <div class="ship-to-section">
        <div class="ship-to-row">
            <div class="ship-to-badge">SHIP<br>TO:</div>
            <div class="ship-to-details">
                <span class="ship-line"><?php echo esc_html($data['ship_name']); ?></span>
                <span class="ship-line"><?php echo esc_html($data['ship_address']); ?></span>
                <span class="ship-line"><?php echo esc_html($data['ship_city_line']); ?></span>
                <?php if (!empty($data['ship_phone'])) : ?>
                    <span class="ship-line"><?php echo esc_html($data['ship_phone']); ?></span>
                <?php endif; ?>
            </div>
        </div>
    </div>

    <hr class="separator">

    <!-- ORDER CODE: MaxiCode + HI Code + Barcode -->
    <div class="order-code-section">
        <div class="maxicode-placeholder">
            <div class="maxicode-symbol">
                <svg viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg">
                    <!-- Bullseye center -->
                    <circle cx="50" cy="50" r="16" fill="none" stroke="#000" stroke-width="3"/>
                    <circle cx="50" cy="50" r="10" fill="none" stroke="#000" stroke-width="3"/>
                    <circle cx="50" cy="50" r="4" fill="#000"/>
                    <!-- Dot grid pattern around bullseye -->
                    <?php
                    // Generate a deterministic dot pattern resembling MaxiCode
                    $dots = [
                        [15,10],[25,10],[35,10],[55,10],[65,10],[75,10],[85,10],
                        [10,20],[20,20],[30,20],[70,20],[80,20],[90,20],
                        [15,30],[25,30],[75,30],[85,30],
                        [10,40],[20,40],[80,40],[90,40],
                        [10,60],[20,60],[80,60],[90,60],
                        [15,70],[25,70],[75,70],[85,70],
                        [10,80],[20,80],[30,80],[70,80],[80,80],[90,80],
                        [15,90],[25,90],[35,90],[55,90],[65,90],[75,90],[85,90],
                        [45,15],[55,15],[45,85],[55,85],
                        [5,50],[95,50],[50,5],[50,95],
                    ];
                    foreach ($dots as $dot) {
                        echo '<rect x="' . ($dot[0] - 2) . '" y="' . ($dot[1] - 2) . '" width="4" height="4" fill="#000"/>';
                    }
                    ?>
                </svg>
            </div>
        </div>
        <div class="order-code-right">
            <div class="hi-code">
                <?php
                // Format: HI XXXXXX RT1
                // Display with spacing similar to sample
                $order_num = $data['order_number'];
                ?>
                HI <?php echo esc_html($order_num); ?> - <span class="rt-suffix">RT1</span>
            </div>
            <div class="order-barcode">
                <svg id="barcode-order"></svg>
            </div>
        </div>
    </div>

    <!-- NEXT DAY SERVICE BAR -->
    <div class="service-section">
        <div class="service-name">NEXT DAY</div>
        <div class="service-number">1</div>
    </div>

    <!-- TRACKING -->
    <div class="tracking-section">
        <div class="tracking-text">TRACKING # <?php echo esc_html($data['tracking']); ?></div>
        <div class="tracking-barcode">
            <svg id="barcode-tracking"></svg>
        </div>
    </div>

    <!-- ADDITIONAL ROUTING -->
    <div class="routing-section">
        <div class="routing-line">ADDITIONAL ROUTING INS.</div>
        <div class="routing-line">ADDITIONAL ROUTING INS.</div>
    </div>

</div>

<script>
document.addEventListener('DOMContentLoaded', function() {
    // Generate order barcode (Code 128)
    try {
        JsBarcode('#barcode-order', <?php echo wp_json_encode('HI' . $data['order_number'] . 'RT1'); ?>, {
            format: 'CODE128',
            displayValue: false,
            height: 40,
            width: 1.5,
            margin: 0
        });
    } catch(e) {
        console.error('Order barcode error:', e);
    }

    // Generate tracking barcode (Code 128)
    try {
        var trackingClean = <?php echo wp_json_encode(str_replace(' ', '', $data['tracking'])); ?>;
        JsBarcode('#barcode-tracking', trackingClean, {
            format: 'CODE128',
            displayValue: false,
            height: 55,
            width: 1.2,
            margin: 0
        });
    } catch(e) {
        console.error('Tracking barcode error:', e);
    }
});
</script>

</body>
</html>
