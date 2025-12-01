# SPVS Cost & Profit v1.4.0 - Upgrade Guide

This guide will help you upgrade from any previous version to v1.4.0 and resolve the duplicate plugin issue.

## The Problem: Two Plugins with the Same Name

If you see two "SPVS Cost & Profit for WooCommerce" plugins in your WordPress admin, it's because:
- The old version (v1.3.0 or earlier) is in one location
- The new version (v1.4.0) is in another location
- WordPress sees them as separate plugins

## Solution: Clean Upgrade

### Method 1: Replace via WordPress Admin (Recommended)

**Step 1: Backup Your Data** ⚠️
```
1. Go to WooCommerce > SPVS Inventory
2. Export your inventory CSV (this includes all costs)
3. Save this file as backup
```

**Step 2: Note Your Current Version**
```
1. Go to Plugins > Installed Plugins
2. Find "SPVS Cost & Profit for WooCommerce"
3. Note which one is currently active
4. Note the version number
```

**Step 3: Deactivate Old Version**
```
1. In Plugins list, click "Deactivate" on the SPVS Cost & Profit plugin
2. Wait for confirmation
```

**Step 4: Delete Old Version**
```
1. After deactivation, click "Delete"
2. Confirm deletion
3. The old plugin files will be removed
```

**Step 5: Install New Version**
```
1. Go to Plugins > Add New > Upload Plugin
2. Choose: spvs-cost-profit-v1.4.0.zip
3. Click "Install Now"
4. Wait for upload and extraction
5. Click "Activate Plugin"
```

**Step 6: Verify Upgrade**
```
1. Go to Plugins > Installed Plugins
2. Verify you see only ONE "SPVS Cost & Profit for WooCommerce"
3. Verify version shows "1.4.0"
4. Go to WooCommerce menu - you should see:
   - SPVS Inventory (existing)
   - SPVS Profit Reports (NEW!)
```

**Step 7: Check Your Data**
```
1. Go to WooCommerce > SPVS Inventory
2. Verify your TCOP/Retail values are still there
3. Edit a product - verify costs are still there
4. Check an old order - verify profit is still calculated
```

### Method 2: Replace via FTP/File Manager

**Step 1: Backup Current Plugin**
```
1. Connect via FTP or cPanel File Manager
2. Navigate to: wp-content/plugins/
3. Find the old SPVS plugin folder (might be named differently)
4. Download/backup the entire folder
```

**Step 2: Delete Old Plugin Folder**
```
1. In WordPress admin: Deactivate the plugin first
2. Via FTP: Delete the old plugin folder completely
3. Common old folder names to look for:
   - spvs-cost-profit/
   - cost-profit-woocommerce/
   - woocommerce-cost-profit/
   - Or any variation
```

**Step 3: Upload New Version**
```
1. Unzip: spvs-cost-profit-v1.4.0.zip on your computer
2. Upload the "spvs-cost-profit" folder to: wp-content/plugins/
3. Ensure the structure is:
   wp-content/plugins/spvs-cost-profit/spvs-cost-profit.php
```

**Step 4: Activate**
```
1. In WordPress admin: Go to Plugins
2. Find "SPVS Cost & Profit for WooCommerce"
3. Click "Activate"
```

### Method 3: Direct File Replacement (Advanced)

If you're sure the folder name is exactly `spvs-cost-profit`:

**Step 1: Deactivate via WordPress**
```
1. Go to Plugins > Installed Plugins
2. Deactivate "SPVS Cost & Profit for WooCommerce"
```

**Step 2: Replace Files**
```
1. Via FTP/File Manager, navigate to:
   wp-content/plugins/spvs-cost-profit/

2. Delete these old files:
   - spvs-cost-profit.php (old version)
   - Any old readme files

3. Upload new files from v1.4.0 ZIP:
   - spvs-cost-profit.php (new version)
   - uninstall.php
   - readme.txt
   - README.md
   - CHANGELOG.md
   - index.php
```

**Step 3: Reactivate**
```
1. Go to Plugins > Installed Plugins
2. Click "Activate" on SPVS Cost & Profit
```

## What's New in v1.4.0?

After upgrading, you'll have access to:

### New Admin Page: Monthly Profit Reports
```
Location: WooCommerce > SPVS Profit Reports

Features:
✓ Interactive profit & revenue charts
✓ Monthly breakdown table
✓ Customizable date range
✓ Profit margin calculations
✓ Average profit per order
✓ CSV export for analysis
```

### All Existing Features Preserved
```
✓ Product cost tracking
✓ Order profit calculations
✓ TCOP/Retail inventory values
✓ CSV import/export
✓ All your existing data
```

## Troubleshooting

### Issue: Still seeing two plugins after upgrade

**Solution:**
```
1. Check different folder names in wp-content/plugins/
2. Search for any folders containing "spvs" or "cost profit"
3. Delete ALL old versions
4. Keep only the new spvs-cost-profit folder
```

### Issue: Data missing after upgrade

**Solution:**
```
1. Don't panic! Data is in your database, not in plugin files
2. Deactivate the new plugin
3. Restore the old plugin from backup
4. Export your data again
5. Try upgrade again, following Method 1 carefully
```

### Issue: White screen or errors after activation

**Solution:**
```
1. Via FTP, rename the plugin folder to disable it:
   spvs-cost-profit → spvs-cost-profit-disabled

2. Check PHP error logs for specific error messages

3. Verify requirements:
   - WordPress 6.0+
   - WooCommerce 7.0+
   - PHP 7.4+

4. If requirements not met, restore old version
```

### Issue: Charts not showing on Profit Reports page

**Solution:**
```
1. Clear browser cache
2. Try a different browser
3. Check browser console for JavaScript errors
4. Verify Chart.js is loading (requires internet connection for CDN)
```

## Verifying Successful Upgrade

After upgrade, verify everything works:

### ✓ Checklist
- [ ] Only ONE plugin shows in Plugins list
- [ ] Version shows 1.4.0
- [ ] WooCommerce menu shows "SPVS Inventory"
- [ ] WooCommerce menu shows "SPVS Profit Reports" (NEW)
- [ ] Existing products still have cost prices
- [ ] TCOP/Retail values are correct
- [ ] Old orders still show profit
- [ ] New profit reports page loads
- [ ] Charts display correctly
- [ ] CSV exports work

## Data Safety

**What's Preserved:**
- ✓ All product cost prices
- ✓ All order profit calculations
- ✓ Inventory totals (TCOP/Retail)
- ✓ All settings

**What's Added:**
- ✓ New monthly profit report page
- ✓ New CSV export options
- ✓ Enhanced admin interface

**What's Removed:**
- ✗ Nothing! (100% backward compatible)

## Rollback Plan

If you need to rollback to v1.3.0:

1. Deactivate v1.4.0
2. Delete v1.4.0 plugin folder
3. Re-upload your backup of v1.3.0
4. Activate v1.3.0

**Note:** You'll lose the monthly profit reports feature, but all your data remains intact.

## Getting Help

If you encounter issues:

1. **Check Error Logs:**
   - WordPress debug.log
   - PHP error logs
   - Browser console

2. **Verify Requirements:**
   - WordPress version
   - WooCommerce version
   - PHP version

3. **Test in Safe Mode:**
   - Deactivate all other plugins
   - Switch to default theme (Twenty Twenty-Four)
   - Test if SPVS works
   - Re-enable plugins one by one

4. **Contact Support:**
   - GitHub Issues: https://github.com/renthemighty/Plugins/issues
   - Include: WP version, WC version, PHP version, error messages

## Post-Upgrade: Explore New Features

### Try the Monthly Profit Reports:
```
1. Go to: WooCommerce > SPVS Profit Reports
2. View last 12 months of data
3. Export to CSV for Excel analysis
4. Compare profit trends month-over-month
```

### Export Your Data:
```
1. Go to: WooCommerce > SPVS Inventory
2. Select desired columns
3. Export to CSV
4. Open in Excel/Google Sheets
```

---

## Quick Reference

**Plugin Details:**
- Name: SPVS Cost & Profit for WooCommerce
- Version: 1.4.0
- Folder: spvs-cost-profit
- Main File: spvs-cost-profit.php
- Text Domain: spvs-cost-profit

**File Locations:**
- Plugin: wp-content/plugins/spvs-cost-profit/
- Data: WordPress database (wp_postmeta, wp_options)

**Admin Pages:**
- WooCommerce > SPVS Inventory
- WooCommerce > SPVS Profit Reports

---

**Last Updated:** 2024-11-30
**Plugin Version:** 1.4.0
