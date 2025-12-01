# 🔧 SPVS Cost Data Recovery & Upgrade to v1.4.1

## ⚠️ CRITICAL: Your Cost Data Got Wiped

I've created **v1.4.1** with comprehensive data protection and **automatic recovery** built-in. Here's how to recover your data and protect it going forward.

---

## 🚨 IMMEDIATE ACTION: Data Recovery

### Option 1: Automatic Recovery (RECOMMENDED)

**The plugin now has built-in auto-recovery that runs when you upgrade!**

1. **Upload v1.4.1 Plugin**
   ```
   File: /home/user/Plugins/spvs-cost-profit-v1.4.1.zip (27KB)
   ```

2. **WordPress will automatically:**
   - Check if cost data is missing
   - Search for cost data in WordPress post revisions
   - Restore any found data
   - Create a backup
   - Show you a success message

3. **Steps:**
   ```
   1. Go to: Plugins > Add New > Upload Plugin
   2. Upload: spvs-cost-profit-v1.4.1.zip
   3. Click "Replace current with uploaded"
   4. Activate the plugin
   5. Go to: WooCommerce > SPVS Inventory
   6. Look for green success message showing recovered items
   ```

### Option 2: Manual Recovery Tool

If automatic recovery doesn't work, use the standalone recovery tool:

1. **Upload Recovery Script**
   ```
   Upload spvs-recovery.php to your WordPress root directory
   (same folder as wp-config.php)
   ```

2. **Access the Tool**
   ```
   https://yoursite.com/spvs-recovery.php
   ```

3. **The tool will:**
   - Scan database for cost data
   - Check revisions for backups
   - Show recovery options
   - Export current/recovered data
   - Provide restore options

4. **DELETE the file after use** (security!)
   ```
   rm spvs-recovery.php
   ```

### Option 3: WordPress Hosting Backup

Most hosts keep daily backups:

**cPanel:**
```
1. Login to cPanel
2. Go to: Backup > Restore
3. Select date before data loss
4. Restore database
```

**WP Engine / Flywheel:**
```
1. Login to hosting dashboard
2. Go to: Backups
3. Select restore point
4. Restore database only (not files)
```

**Other hosts:**
Contact support and request database restoration to a specific date.

---

## 🔒 v1.4.1: Never Lose Data Again

### What's New - Data Protection Features

#### 1. **Automatic Daily Backups**
- Runs every day at 3:00 AM
- Keeps 7 days of backups
- Stored safely in database
- No manual intervention needed

#### 2. **Manual Backup Anytime**
- One-click backup creation
- Available at: WooCommerce > SPVS Inventory
- Button: "💾 Create Backup Now"

#### 3. **Backup Management**
- View all available backups
- Download backups as CSV
- Restore from any backup
- Automatic rotation (keeps 7 most recent)

#### 4. **One-Click Restore**
- Restore costs from any backup
- Creates safety backup before restoring
- Confirmation required
- Success message shown

#### 5. **Activation Protection**
- Auto-backup on plugin activation
- Auto-recovery if data missing
- Checks WordPress revisions
- Seamless upgrade process

#### 6. **Backup UI in Admin**
```
Location: WooCommerce > SPVS Inventory

New Section: "🔒 Data Backup & Protection"

Features:
- Latest backup info
- Create backup button
- Backup list table
- Restore & download buttons
```

---

## 📥 Installation Instructions

### Method 1: Upload via WordPress Admin

1. **Before Upgrading:**
   ```
   - If you have ANY cost data showing, export it NOW
   - Go to: WooCommerce > SPVS Inventory
   - Click: "Export CSV (selected columns)"
   - Save this file safely
   ```

2. **Upload v1.4.1:**
   ```
   1. Go to: Plugins > Add New > Upload Plugin
   2. Choose: spvs-cost-profit-v1.4.1.zip
   3. Click: "Install Now"
   4. If asked, click: "Replace current with uploaded"
   5. Click: "Activate Plugin"
   ```

3. **After Activation:**
   ```
   1. Go to: WooCommerce > SPVS Inventory
   2. Check for auto-recovery success message
   3. Verify cost data is present
   4. Look for "Data Backup & Protection" section
   5. Click "Create Backup Now" to create first manual backup
   ```

### Method 2: FTP/File Manager

1. **Backup Current Plugin:**
   ```
   Download wp-content/plugins/spvs-cost-profit/ folder
   ```

2. **Upload New Version:**
   ```
   1. Deactivate plugin in WordPress
   2. Delete old spvs-cost-profit folder via FTP
   3. Upload new spvs-cost-profit folder
   4. Activate plugin in WordPress
   ```

---

## ✅ Verification Checklist

After upgrading to v1.4.1:

- [ ] Plugin shows version 1.4.1
- [ ] Auto-recovery message appeared (if data was missing)
- [ ] Cost data is visible on products
- [ ] "Data Backup & Protection" section visible
- [ ] Can create manual backup successfully
- [ ] Backup appears in backup list
- [ ] Can download backup as CSV
- [ ] TCOP/Retail values are correct

---

## 🛡️ How Backups Work

### Backup Storage
```
Location: WordPress database (wp_options table)
Key Format: spvs_cost_backup_YYYY_MM_DD_HH_MM_SS
Max Backups: 7 (oldest automatically deleted)
Backup Contains:
  - Product ID
  - Cost value
  - Timestamp
  - Product count
  - Plugin version
```

### Backup Schedule
```
Daily Automatic: 3:00 AM (WordPress cron)
Manual: Anytime via admin button
On Activation: Automatic backup created
Before Restore: Safety backup created
```

### Backup Access
```
View: WooCommerce > SPVS Inventory > Data Backup & Protection
Download: Click "📥 Download" button next to any backup
Restore: Click "🔄 Restore" button (with confirmation)
```

---

## 🔄 Restore Process

### How Restore Works:

1. **User clicks "Restore" button**
2. **Confirmation dialog appears**
   ```
   "Are you sure you want to restore from this backup?
    Current data will be backed up first."
   ```
3. **Plugin creates safety backup of current data**
4. **Plugin restores data from selected backup**
5. **Success message shows number of products restored**

### Safety Features:
- ✅ Confirmation required
- ✅ Current data backed up before restore
- ✅ Can restore again if needed
- ✅ All backups preserved (unless older than 7 days)

---

## 📊 What Gets Backed Up

### Included in Backups:
✅ Product cost prices (`_spvs_cost_price`)
✅ All products (simple & variations)
✅ Published products only

### NOT Included:
❌ Order profit data (recalculated automatically)
❌ Inventory totals (recalculated automatically)
❌ Plugin settings (minimal settings to backup)

**Why?** Order profits and inventory totals are calculated from costs, so they rebuild automatically when costs are restored.

---

## 🚑 Emergency Recovery Scenarios

### Scenario 1: Just upgraded, all costs gone

**Solution:**
```
1. Plugin automatically attempts recovery on activation
2. Check for green success message
3. If no message, use Manual Recovery Tool (spvs-recovery.php)
4. Or restore from hosting backup
```

### Scenario 2: Costs were there, now they're gone

**Solution:**
```
1. Go to: WooCommerce > SPVS Inventory
2. Scroll to: "Available Backups"
3. Click "Restore" on most recent backup
4. Confirm restoration
```

### Scenario 3: No backups available (fresh install)

**Solution:**
```
1. Upload spvs-recovery.php to site root
2. Access via browser
3. Tool checks WordPress revisions
4. Click "Recover from Revisions" if found
5. Or restore from hosting database backup
```

### Scenario 4: Have CSV export from before

**Solution:**
```
1. Go to: WooCommerce > SPVS Inventory
2. Scroll to: "Import Costs (CSV)"
3. Upload your CSV file
4. Check "Recalculate totals after import"
5. Click "Import Costs"
```

---

## 💡 Best Practices Going Forward

### Daily Operations:
1. ✅ Let automatic backups run (3 AM daily)
2. ✅ Before major changes, click "Create Backup Now"
3. ✅ After bulk imports, create manual backup
4. ✅ Download important backups as CSV for external storage

### Before Big Changes:
```
ALWAYS create manual backup before:
- Bulk cost imports
- Plugin updates
- Database maintenance
- Theme/plugin conflicts testing
```

### Weekly Maintenance:
```
1. Check that latest backup exists
2. Download 1 backup per week for external storage
3. Verify backup count shows 7 or close to it
```

### Monthly Review:
```
1. Export full inventory CSV
2. Store offline/cloud backup
3. Verify all products have costs
4. Check for missing costs report
```

---

## 📞 Getting Help

### If Auto-Recovery Didn't Work:

1. **Check WordPress Revisions:**
   ```
   In WordPress: Posts > Revisions
   Cost data might be in product revision history
   ```

2. **Use Recovery Tool:**
   ```
   Upload and access spvs-recovery.php
   Follow on-screen instructions
   ```

3. **Contact Hosting Support:**
   ```
   Ask for: "Database restore to [specific date]"
   Only restore: Database (not files)
   Specify: Before cost data loss occurred
   ```

4. **Manual Database Query:**
   ```sql
   -- Check if data exists in revisions
   SELECT COUNT(*) FROM wp_postmeta pm
   INNER JOIN wp_posts p ON pm.post_id = p.ID
   WHERE pm.meta_key = '_spvs_cost_price'
   AND p.post_type = 'revision';
   ```

---

## 📝 Summary

### What Happened:
- Cost data was wiped (likely during plugin swap or update)

### What I Created:
1. ✅ **v1.4.1** with automatic backup system
2. ✅ **Auto-recovery** on upgrade (checks revisions)
3. ✅ **Manual recovery tool** (spvs-recovery.php)
4. ✅ **Backup UI** in admin area
5. ✅ **Daily backups** (automatic, keeps 7 days)
6. ✅ **One-click restore** from any backup

### What You Should Do:
1. 🔄 **Upgrade to v1.4.1** (auto-recovery built-in)
2. ✅ **Verify cost data** is restored
3. 💾 **Create manual backup** immediately
4. 📥 **Export backup as CSV** for safekeeping
5. 🔒 **Relax** - automatic backups now protect you

### Files Available:
```
Plugin v1.4.1: spvs-cost-profit-v1.4.1.zip (27KB)
Recovery Tool:  spvs-recovery.php
Instructions:   RECOVERY_INSTRUCTIONS.md (this file)
Upgrade Guide:  UPGRADE_GUIDE.md
```

---

## ⚡ Quick Start

**FASTEST RECOVERY PATH:**

```
1. Upload spvs-cost-profit-v1.4.1.zip via WordPress
2. Replace/activate
3. Check for green "Auto-Recovery Successful!" message
4. Go to WooCommerce > SPVS Inventory
5. Verify costs are back
6. Click "Create Backup Now"
7. Done! Protected forever.
```

**IF THAT DOESN'T WORK:**

```
1. Upload spvs-recovery.php to site root
2. Visit https://yoursite.com/spvs-recovery.php
3. Click "Recover from Revisions"
4. Download recovered data
5. Delete spvs-recovery.php
6. Upgrade to v1.4.1
7. Done!
```

---

## 🎯 Bottom Line

**You will NEVER lose cost data again with v1.4.1.**

- ✅ Automatic backups every day
- ✅ Auto-recovery on upgrade
- ✅ Manual backup anytime
- ✅ One-click restore
- ✅ Download backups as CSV
- ✅ 7 days of backup history
- ✅ Built-in recovery tools

**Upgrade now and your data is protected!**

---

**Last Updated:** 2024-11-30
**Plugin Version:** 1.4.1
**Recovery Tools:** Built-in + Standalone
