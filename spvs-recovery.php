<?php
/**
 * SPVS Cost Data Recovery & Diagnostic Tool
 *
 * IMPORTANT: Place this file in your WordPress root directory and access via browser
 * URL: https://yoursite.com/spvs-recovery.php
 *
 * This tool will:
 * 1. Check for cost data in database
 * 2. Look for backups in various places
 * 3. Attempt recovery if data found
 * 4. Export any found data for safekeeping
 */

// Load WordPress
require_once('wp-load.php');

// Security check
if (!current_user_can('manage_options')) {
    wp_die('Access Denied: Administrator access required.');
}

global $wpdb;

// Set long execution time for large databases
set_time_limit(300);

?>
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>SPVS Cost Data Recovery Tool</title>
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; max-width: 1200px; margin: 20px auto; padding: 20px; background: #f0f0f1; }
        .container { background: white; padding: 30px; border-radius: 8px; box-shadow: 0 1px 3px rgba(0,0,0,0.1); margin-bottom: 20px; }
        h1 { color: #1d2327; margin-top: 0; }
        h2 { color: #2271b1; border-bottom: 2px solid #2271b1; padding-bottom: 10px; }
        .alert { padding: 15px; border-radius: 5px; margin: 15px 0; }
        .alert-success { background: #d4edda; border-left: 4px solid #28a745; color: #155724; }
        .alert-warning { background: #fff3cd; border-left: 4px solid #ffc107; color: #856404; }
        .alert-danger { background: #f8d7da; border-left: 4px solid #dc3545; color: #721c24; }
        .alert-info { background: #d1ecf1; border-left: 4px solid #17a2b8; color: #0c5460; }
        table { width: 100%; border-collapse: collapse; margin: 15px 0; }
        th, td { padding: 12px; text-align: left; border-bottom: 1px solid #ddd; }
        th { background: #f8f9fa; font-weight: 600; }
        .btn { display: inline-block; padding: 10px 20px; background: #2271b1; color: white; text-decoration: none; border-radius: 5px; border: none; cursor: pointer; font-size: 14px; }
        .btn:hover { background: #135e96; }
        .btn-success { background: #28a745; }
        .btn-success:hover { background: #218838; }
        .btn-warning { background: #ffc107; color: #000; }
        .btn-warning:hover { background: #e0a800; }
        .code { background: #f5f5f5; padding: 15px; border-radius: 5px; font-family: monospace; overflow-x: auto; }
        .stats { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 15px; margin: 20px 0; }
        .stat-box { background: #f8f9fa; padding: 20px; border-radius: 5px; border-left: 4px solid #2271b1; }
        .stat-value { font-size: 32px; font-weight: bold; color: #2271b1; }
        .stat-label { color: #666; font-size: 14px; }
        pre { background: #f5f5f5; padding: 15px; border-radius: 5px; overflow-x: auto; }
    </style>
</head>
<body>
    <div class="container">
        <h1>🔍 SPVS Cost Data Recovery Tool</h1>
        <p>This tool will scan your database for cost data and attempt recovery.</p>
    </div>

    <?php
    // Step 1: Check current cost data
    echo '<div class="container">';
    echo '<h2>Step 1: Current Cost Data Status</h2>';

    $current_costs = $wpdb->get_results("
        SELECT pm.post_id, pm.meta_value as cost, p.post_title, p.post_type
        FROM {$wpdb->postmeta} pm
        INNER JOIN {$wpdb->posts} p ON pm.post_id = p.ID
        WHERE pm.meta_key = '_spvs_cost_price'
        AND p.post_type IN ('product', 'product_variation')
        ORDER BY pm.post_id
    ");

    $current_count = count($current_costs);

    if ($current_count > 0) {
        echo '<div class="alert alert-success">';
        echo '<strong>✅ Good News!</strong> Found ' . $current_count . ' products with cost data still in database.';
        echo '</div>';
    } else {
        echo '<div class="alert alert-danger">';
        echo '<strong>⚠️ Alert!</strong> No cost data found in current database. Checking for backups...';
        echo '</div>';
    }
    echo '</div>';

    // Step 2: Check for backup/revision data
    echo '<div class="container">';
    echo '<h2>Step 2: Searching for Backup Data</h2>';

    // Check post revisions for cost meta
    $revision_costs = $wpdb->get_results("
        SELECT pm.post_id, pm.meta_value as cost, p.post_parent, p.post_title, p.post_modified
        FROM {$wpdb->postmeta} pm
        INNER JOIN {$wpdb->posts} p ON pm.post_id = p.ID
        WHERE pm.meta_key = '_spvs_cost_price'
        AND p.post_type = 'revision'
        ORDER BY p.post_modified DESC
    ");

    $revision_count = count($revision_costs);

    if ($revision_count > 0) {
        echo '<div class="alert alert-info">';
        echo '<strong>💾 Found Backup Data!</strong> Discovered ' . $revision_count . ' cost entries in post revisions.';
        echo '</div>';
    }

    // Check for any meta with similar keys (in case of typos or variations)
    $similar_meta = $wpdb->get_results("
        SELECT DISTINCT meta_key, COUNT(*) as count
        FROM {$wpdb->postmeta}
        WHERE meta_key LIKE '%cost%' OR meta_key LIKE '%spvs%'
        GROUP BY meta_key
    ");

    if (!empty($similar_meta)) {
        echo '<h3>Related Meta Keys Found:</h3>';
        echo '<table><thead><tr><th>Meta Key</th><th>Count</th></tr></thead><tbody>';
        foreach ($similar_meta as $meta) {
            echo '<tr><td>' . esc_html($meta->meta_key) . '</td><td>' . esc_html($meta->count) . '</td></tr>';
        }
        echo '</tbody></table>';
    }
    echo '</div>';

    // Step 3: Check for database backups
    echo '<div class="container">';
    echo '<h2>Step 3: Database Backup Tables</h2>';

    $backup_tables = $wpdb->get_results("SHOW TABLES LIKE '{$wpdb->prefix}%backup%'");

    if (!empty($backup_tables)) {
        echo '<div class="alert alert-info">';
        echo '<strong>Found backup tables:</strong><br>';
        foreach ($backup_tables as $table) {
            echo '• ' . esc_html(array_values((array)$table)[0]) . '<br>';
        }
        echo '</div>';
    } else {
        echo '<div class="alert alert-warning">';
        echo 'No automatic backup tables found. Check your hosting backup system.';
        echo '</div>';
    }
    echo '</div>';

    // Step 4: Recovery Actions
    echo '<div class="container">';
    echo '<h2>Step 4: Recovery Options</h2>';

    if (isset($_POST['recover_from_revisions']) && $revision_count > 0) {
        echo '<div class="alert alert-info">Processing recovery from revisions...</div>';

        $recovered = 0;
        $processed_parents = array();

        foreach ($revision_costs as $rev) {
            $parent_id = $rev->post_parent;
            if ($parent_id && !in_array($parent_id, $processed_parents)) {
                $current_cost = get_post_meta($parent_id, '_spvs_cost_price', true);
                if (empty($current_cost)) {
                    update_post_meta($parent_id, '_spvs_cost_price', $rev->cost);
                    $recovered++;
                    $processed_parents[] = $parent_id;
                }
            }
        }

        echo '<div class="alert alert-success">';
        echo '<strong>✅ Recovery Complete!</strong> Restored cost data for ' . $recovered . ' products.';
        echo '</div>';

        // Refresh current costs
        $current_costs = $wpdb->get_results("
            SELECT pm.post_id, pm.meta_value as cost, p.post_title
            FROM {$wpdb->postmeta} pm
            INNER JOIN {$wpdb->posts} p ON pm.post_id = p.ID
            WHERE pm.meta_key = '_spvs_cost_price'
            AND p.post_type IN ('product', 'product_variation')
            ORDER BY pm.post_id
        ");
        $current_count = count($current_costs);
    }

    if ($revision_count > 0 && !isset($_POST['recover_from_revisions'])) {
        echo '<form method="post">';
        echo '<button type="submit" name="recover_from_revisions" class="btn btn-success">🔄 Recover Cost Data from Revisions</button>';
        echo '<p class="alert alert-info">This will restore cost data from post revisions for products that are missing cost values.</p>';
        echo '</form>';
    }
    echo '</div>';

    // Step 5: Export current data
    if ($current_count > 0) {
        echo '<div class="container">';
        echo '<h2>Step 5: Export Current Data (BACKUP)</h2>';

        if (isset($_GET['export_csv'])) {
            header('Content-Type: text/csv; charset=utf-8');
            header('Content-Disposition: attachment; filename=spvs-cost-backup-' . date('Y-m-d-His') . '.csv');
            $output = fopen('php://output', 'w');
            fputcsv($output, array('Product ID', 'Product Name', 'Type', 'SKU', 'Cost'));

            foreach ($current_costs as $item) {
                $product = wc_get_product($item->post_id);
                if ($product) {
                    fputcsv($output, array(
                        $item->post_id,
                        $item->post_title,
                        $item->post_type,
                        $product->get_sku(),
                        $item->cost
                    ));
                }
            }
            fclose($output);
            exit;
        }

        echo '<a href="?export_csv=1" class="btn btn-warning">📥 Download Cost Data Backup (CSV)</a>';
        echo '<p class="alert alert-warning"><strong>Important:</strong> Download this backup NOW before making any changes!</p>';
        echo '</div>';
    }

    // Step 6: Display current data
    if ($current_count > 0) {
        echo '<div class="container">';
        echo '<h2>Step 6: Current Cost Data</h2>';
        echo '<p>Showing first 50 products with cost data:</p>';
        echo '<table>';
        echo '<thead><tr><th>ID</th><th>Product Name</th><th>Type</th><th>Cost</th></tr></thead>';
        echo '<tbody>';

        $display_costs = array_slice($current_costs, 0, 50);
        foreach ($display_costs as $item) {
            echo '<tr>';
            echo '<td>' . esc_html($item->post_id) . '</td>';
            echo '<td>' . esc_html($item->post_title) . '</td>';
            echo '<td>' . esc_html($item->post_type) . '</td>';
            echo '<td>' . esc_html(wc_price($item->cost)) . '</td>';
            echo '</tr>';
        }

        if ($current_count > 50) {
            echo '<tr><td colspan="4"><em>... and ' . ($current_count - 50) . ' more products</em></td></tr>';
        }

        echo '</tbody></table>';
        echo '</div>';
    }

    // Summary Statistics
    echo '<div class="container">';
    echo '<h2>Summary Statistics</h2>';
    echo '<div class="stats">';
    echo '<div class="stat-box">';
    echo '<div class="stat-value">' . $current_count . '</div>';
    echo '<div class="stat-label">Products with Cost Data</div>';
    echo '</div>';
    echo '<div class="stat-box">';
    echo '<div class="stat-value">' . $revision_count . '</div>';
    echo '<div class="stat-label">Costs in Revisions (Backup)</div>';
    echo '</div>';
    echo '</div>';
    echo '</div>';

    // Instructions
    echo '<div class="container">';
    echo '<h2>📋 Next Steps</h2>';
    echo '<ol>';
    echo '<li><strong>Export Current Data:</strong> Click the "Download Cost Data Backup" button above to save your current data.</li>';
    echo '<li><strong>Check Your Hosting Backups:</strong> Most hosts keep daily backups. Restore from before the issue occurred.</li>';
    echo '<li><strong>Recover from Revisions:</strong> If data found in revisions, use the recovery button above.</li>';
    echo '<li><strong>Manual Recovery:</strong> If you have a previous CSV export, use the plugin\'s import feature.</li>';
    echo '</ol>';

    echo '<h3>Prevention for Future:</h3>';
    echo '<div class="alert alert-info">';
    echo '<strong>The enhanced plugin (v1.4.1) will include:</strong><br>';
    echo '• Automatic daily backups of cost data<br>';
    echo '• Pre-upgrade safety check and backup<br>';
    echo '• Data preservation during plugin updates<br>';
    echo '• One-click restore from backups<br>';
    echo '</div>';
    echo '</div>';

    // Cleanup notice
    echo '<div class="container">';
    echo '<div class="alert alert-danger">';
    echo '<strong>⚠️ SECURITY NOTICE:</strong> After using this tool, DELETE this file from your server for security!<br>';
    echo '<code>rm spvs-recovery.php</code> or delete via FTP.';
    echo '</div>';
    echo '</div>';
    ?>
</body>
</html>
