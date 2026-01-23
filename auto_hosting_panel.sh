#!/bin/bash

###############################################################################
# RizzDevs Hosting Panel - Full Auto Installation Script
# Zero Coding Required - Automated CI4 Code Generation
# Domain: rizzdevs.biz.id | Admin: adminriski.rizzdevs.biz.id
###############################################################################

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
MAIN_DOMAIN="rizzdevs.biz.id"
ADMIN_SUBDOMAIN="adminriski.rizzdevs.biz.id"
PANEL_DIR="/var/www/rizzdevs-panel"
DB_NAME="rizzdevs_panel"
DB_USER="rizzdevs_user"
DB_PASS=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
ADMIN_EMAIL="admin@rizzdevs.biz.id"
ADMIN_PASS=$(openssl rand -base64 16 | tr -d "=+/" | cut -c1-12)

# Print functions
print_status() { echo -e "${GREEN}[✓]${NC} $1"; }
print_error() { echo -e "${RED}[✗]${NC} $1"; exit 1; }
print_warning() { echo -e "${YELLOW}[!]${NC} $1"; }
print_info() { echo -e "${BLUE}[i]${NC} $1"; }

# Banner
clear
cat << "EOF"
╔═══════════════════════════════════════════════════════════╗
║                                                           ║
║        RizzDevs Hosting Panel Auto Installer v1.0        ║
║                                                           ║
║  Automated Installation - Zero Coding Required           ║
║  Full cPanel-like Features with CloudFlare Integration   ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝
EOF

echo ""
print_info "Starting installation process..."
sleep 2

# Check root
[[ $EUID -ne 0 ]] && print_error "This script must be run as root!"

# Get Cloudflare credentials
echo ""
print_warning "CloudFlare Configuration Required"
read -p "Enter CloudFlare API Token: " CLOUDFLARE_API_TOKEN
read -p "Enter CloudFlare Zone ID: " CLOUDFLARE_ZONE_ID

[[ -z "$CLOUDFLARE_API_TOKEN" ]] && print_error "CloudFlare API Token is required!"
[[ -z "$CLOUDFLARE_ZONE_ID" ]] && print_error "CloudFlare Zone ID is required!"

echo ""
print_info "Installing system dependencies..."

# Update system
apt-get update -qq
apt-get upgrade -y -qq

# Install required packages
print_status "Installing Nginx, PHP 8.2, MariaDB, and tools..."
apt-get install -y -qq \
    nginx \
    mariadb-server \
    php8.2-fpm \
    php8.2-mysql \
    php8.2-curl \
    php8.2-xml \
    php8.2-mbstring \
    php8.2-zip \
    php8.2-intl \
    php8.2-gd \
    php8.2-cli \
    certbot \
    python3-certbot-nginx \
    python3-certbot-dns-cloudflare \
    git \
    curl \
    wget \
    unzip \
    composer \
    jq \
    dnsutils

print_status "System packages installed successfully"

# Secure MariaDB
print_status "Configuring MariaDB..."
mysql -e "DELETE FROM mysql.user WHERE User='';"
mysql -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');"
mysql -e "DROP DATABASE IF EXISTS test;"
mysql -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';"
mysql -e "CREATE DATABASE IF NOT EXISTS ${DB_NAME};"
mysql -e "CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';"
mysql -e "GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';"
mysql -e "FLUSH PRIVILEGES;"

print_status "Database created and secured"

# Create project directory
print_status "Creating project directory..."
mkdir -p ${PANEL_DIR}
cd ${PANEL_DIR}

# Install CodeIgniter 4
print_status "Installing CodeIgniter 4 framework..."
composer create-project codeigniter4/appstarter . --no-interaction --quiet

# Configure CI4 environment
print_status "Configuring CodeIgniter 4..."
cp env .env

cat > .env << EOF
# ENVIRONMENT
CI_ENVIRONMENT = production

# APP
app.baseURL = 'https://${MAIN_DOMAIN}/'
app.indexPage = ''
app.forceGlobalSecureRequests = true

# DATABASE
database.default.hostname = localhost
database.default.database = ${DB_NAME}
database.default.username = ${DB_USER}
database.default.password = ${DB_PASS}
database.default.DBDriver = MySQLi
database.default.DBPrefix = 
database.default.port = 3306

# ENCRYPTION
encryption.key = $(php -r "echo bin2hex(random_bytes(32));")

# SESSION
session.driver = 'CodeIgniter\Session\Handlers\DatabaseHandler'
session.cookieName = 'rizzdevs_session'
session.expiration = 7200
session.savePath = 'ci_sessions'

# CLOUDFLARE
cloudflare.apiToken = ${CLOUDFLARE_API_TOKEN}
cloudflare.zoneId = ${CLOUDFLARE_ZONE_ID}
cloudflare.mainDomain = ${MAIN_DOMAIN}
EOF

# Create database tables
print_status "Creating database schema..."
mysql ${DB_NAME} << 'EOSQL'
-- Users table
CREATE TABLE IF NOT EXISTS users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    password VARCHAR(255) NOT NULL,
    full_name VARCHAR(100),
    role ENUM('admin', 'user') DEFAULT 'user',
    status ENUM('active', 'suspended', 'inactive') DEFAULT 'active',
    disk_quota BIGINT DEFAULT 5368709120,
    disk_used BIGINT DEFAULT 0,
    bandwidth_quota BIGINT DEFAULT 107374182400,
    bandwidth_used BIGINT DEFAULT 0,
    max_projects INT DEFAULT 10,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_email (email),
    INDEX idx_username (username)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Projects table
CREATE TABLE IF NOT EXISTS projects (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL,
    project_name VARCHAR(100) NOT NULL,
    subdomain VARCHAR(100) UNIQUE NOT NULL,
    full_domain VARCHAR(255) NOT NULL,
    document_root VARCHAR(255) NOT NULL,
    php_version VARCHAR(10) DEFAULT '8.2',
    ssl_enabled TINYINT(1) DEFAULT 0,
    ssl_cert_path VARCHAR(255),
    ssl_key_path VARCHAR(255),
    status ENUM('active', 'suspended', 'deleted') DEFAULT 'active',
    disk_used BIGINT DEFAULT 0,
    bandwidth_used BIGINT DEFAULT 0,
    cloudflare_record_id VARCHAR(100),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    INDEX idx_user_id (user_id),
    INDEX idx_subdomain (subdomain)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Databases table
CREATE TABLE IF NOT EXISTS user_databases (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL,
    project_id INT,
    db_name VARCHAR(64) NOT NULL,
    db_user VARCHAR(32) NOT NULL,
    db_password VARCHAR(255) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE SET NULL,
    INDEX idx_user_id (user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Session table for CI4
CREATE TABLE IF NOT EXISTS ci_sessions (
    id VARCHAR(128) NOT NULL PRIMARY KEY,
    ip_address VARCHAR(45) NOT NULL,
    timestamp BIGINT UNSIGNED DEFAULT 0 NOT NULL,
    data BLOB NOT NULL,
    INDEX ci_sessions_timestamp (timestamp)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Activity logs
CREATE TABLE IF NOT EXISTS activity_logs (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT,
    action VARCHAR(100) NOT NULL,
    description TEXT,
    ip_address VARCHAR(45),
    user_agent TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL,
    INDEX idx_user_id (user_id),
    INDEX idx_created_at (created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Settings table
CREATE TABLE IF NOT EXISTS settings (
    id INT AUTO_INCREMENT PRIMARY KEY,
    setting_key VARCHAR(100) UNIQUE NOT NULL,
    setting_value TEXT,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Insert default admin
INSERT INTO users (username, email, password, full_name, role, disk_quota, max_projects) 
VALUES ('admin', '${ADMIN_EMAIL}', '\$2y\$10\$', 'Administrator', 'admin', 107374182400, 999);
EOSQL

# Update admin password
HASHED_PASS=$(php -r "echo password_hash('${ADMIN_PASS}', PASSWORD_BCRYPT);")
mysql ${DB_NAME} -e "UPDATE users SET password = '${HASHED_PASS}' WHERE username = 'admin';"

print_status "Database schema created"

# Generate CI4 Controllers
print_status "Generating Controllers..."

# Auth Controller
cat > app/Controllers/Auth.php << 'EOPHP'
<?php

namespace App\Controllers;

use App\Models\UserModel;
use CodeIgniter\Controller;

class Auth extends Controller
{
    public function login()
    {
        if (session()->get('logged_in')) {
            return redirect()->to(session()->get('role') === 'admin' ? '/admin/dashboard' : '/dashboard');
        }

        if ($this->request->getMethod() === 'post') {
            $userModel = new UserModel();
            $email = $this->request->getPost('email');
            $password = $this->request->getPost('password');

            $user = $userModel->where('email', $email)->first();

            if ($user && password_verify($password, $user['password'])) {
                if ($user['status'] !== 'active') {
                    return redirect()->back()->with('error', 'Account is suspended or inactive');
                }

                session()->set([
                    'user_id' => $user['id'],
                    'username' => $user['username'],
                    'email' => $user['email'],
                    'role' => $user['role'],
                    'logged_in' => true
                ]);

                $this->logActivity($user['id'], 'login', 'User logged in');

                return redirect()->to($user['role'] === 'admin' ? '/admin/dashboard' : '/dashboard');
            }

            return redirect()->back()->with('error', 'Invalid credentials');
        }

        return view('auth/login');
    }

    public function logout()
    {
        $this->logActivity(session()->get('user_id'), 'logout', 'User logged out');
        session()->destroy();
        return redirect()->to('/login');
    }

    public function register()
    {
        if ($this->request->getMethod() === 'post') {
            $userModel = new UserModel();

            $data = [
                'username' => $this->request->getPost('username'),
                'email' => $this->request->getPost('email'),
                'password' => password_hash($this->request->getPost('password'), PASSWORD_BCRYPT),
                'full_name' => $this->request->getPost('full_name'),
                'role' => 'user'
            ];

            if ($userModel->insert($data)) {
                return redirect()->to('/login')->with('success', 'Registration successful! Please login.');
            }

            return redirect()->back()->with('error', 'Registration failed');
        }

        return view('auth/register');
    }

    private function logActivity($userId, $action, $description)
    {
        $db = \Config\Database::connect();
        $db->table('activity_logs')->insert([
            'user_id' => $userId,
            'action' => $action,
            'description' => $description,
            'ip_address' => $this->request->getIPAddress(),
            'user_agent' => $this->request->getUserAgent()->getAgentString()
        ]);
    }
}
EOPHP

# User Dashboard Controller
cat > app/Controllers/Dashboard.php << 'EOPHP'
<?php

namespace App\Controllers;

use App\Models\ProjectModel;
use App\Libraries\CloudflareManager;
use App\Libraries\NginxManager;

class Dashboard extends BaseController
{
    protected $projectModel;
    protected $cloudflare;
    protected $nginx;

    public function __construct()
    {
        $this->projectModel = new ProjectModel();
        $this->cloudflare = new CloudflareManager();
        $this->nginx = new NginxManager();
    }

    public function index()
    {
        $data['projects'] = $this->projectModel->where('user_id', session()->get('user_id'))->findAll();
        $data['user'] = model('UserModel')->find(session()->get('user_id'));
        
        return view('dashboard/index', $data);
    }

    public function projects()
    {
        $data['projects'] = $this->projectModel->where('user_id', session()->get('user_id'))->findAll();
        return view('dashboard/projects', $data);
    }

    public function createProject()
    {
        if ($this->request->getMethod() === 'post') {
            $projectName = $this->request->getPost('project_name');
            $subdomain = strtolower(preg_replace('/[^a-zA-Z0-9]/', '', $projectName));
            $fullDomain = $subdomain . '.' . env('cloudflare.mainDomain');

            // Create DNS record
            $dnsResult = $this->cloudflare->createDnsRecord($subdomain);
            
            if (!$dnsResult['success']) {
                return redirect()->back()->with('error', 'Failed to create DNS record');
            }

            // Create project directory
            $docRoot = "/var/www/projects/{$subdomain}";
            exec("mkdir -p {$docRoot}/public");
            exec("chown -R www-data:www-data {$docRoot}");

            // Create default index
            file_put_contents("{$docRoot}/public/index.php", "<?php echo '<h1>Welcome to {$projectName}</h1>'; ?>");

            // Create nginx config
            $this->nginx->createVirtualHost($subdomain, $fullDomain, $docRoot);

            // Install SSL
            $this->nginx->installSSL($fullDomain);

            // Save to database
            $projectData = [
                'user_id' => session()->get('user_id'),
                'project_name' => $projectName,
                'subdomain' => $subdomain,
                'full_domain' => $fullDomain,
                'document_root' => $docRoot,
                'cloudflare_record_id' => $dnsResult['record_id'],
                'ssl_enabled' => 1
            ];

            $this->projectModel->insert($projectData);

            return redirect()->to('/dashboard/projects')->with('success', "Project created: {$fullDomain}");
        }

        return view('dashboard/create_project');
    }

    public function deleteProject($id)
    {
        $project = $this->projectModel->where('user_id', session()->get('user_id'))->find($id);
        
        if (!$project) {
            return redirect()->back()->with('error', 'Project not found');
        }

        // Delete DNS record
        $this->cloudflare->deleteDnsRecord($project['cloudflare_record_id']);

        // Delete nginx config
        $this->nginx->deleteVirtualHost($project['subdomain']);

        // Delete project files
        exec("rm -rf {$project['document_root']}");

        // Delete from database
        $this->projectModel->delete($id);

        return redirect()->to('/dashboard/projects')->with('success', 'Project deleted successfully');
    }
}
EOPHP

# Admin Dashboard Controller
cat > app/Controllers/Admin/Dashboard.php << 'EOPHP'
<?php

namespace App\Controllers\Admin;

use App\Controllers\BaseController;
use App\Models\UserModel;
use App\Models\ProjectModel;

class Dashboard extends BaseController
{
    protected $userModel;
    protected $projectModel;

    public function __construct()
    {
        $this->userModel = new UserModel();
        $this->projectModel = new ProjectModel();
    }

    public function index()
    {
        $data['total_users'] = $this->userModel->where('role', 'user')->countAllResults();
        $data['total_projects'] = $this->projectModel->countAllResults();
        $data['recent_users'] = $this->userModel->orderBy('created_at', 'DESC')->limit(5)->findAll();
        $data['recent_projects'] = $this->projectModel->orderBy('created_at', 'DESC')->limit(5)->findAll();

        return view('admin/dashboard', $data);
    }

    public function users()
    {
        $data['users'] = $this->userModel->findAll();
        return view('admin/users', $data);
    }

    public function createUser()
    {
        if ($this->request->getMethod() === 'post') {
            $userData = [
                'username' => $this->request->getPost('username'),
                'email' => $this->request->getPost('email'),
                'password' => password_hash($this->request->getPost('password'), PASSWORD_BCRYPT),
                'full_name' => $this->request->getPost('full_name'),
                'role' => $this->request->getPost('role'),
                'disk_quota' => $this->request->getPost('disk_quota') * 1073741824,
                'max_projects' => $this->request->getPost('max_projects')
            ];

            $this->userModel->insert($userData);
            return redirect()->to('/admin/users')->with('success', 'User created successfully');
        }

        return view('admin/create_user');
    }

    public function editUser($id)
    {
        $user = $this->userModel->find($id);

        if ($this->request->getMethod() === 'post') {
            $userData = [
                'username' => $this->request->getPost('username'),
                'email' => $this->request->getPost('email'),
                'full_name' => $this->request->getPost('full_name'),
                'role' => $this->request->getPost('role'),
                'status' => $this->request->getPost('status'),
                'disk_quota' => $this->request->getPost('disk_quota') * 1073741824,
                'max_projects' => $this->request->getPost('max_projects')
            ];

            if ($this->request->getPost('password')) {
                $userData['password'] = password_hash($this->request->getPost('password'), PASSWORD_BCRYPT);
            }

            $this->userModel->update($id, $userData);
            return redirect()->to('/admin/users')->with('success', 'User updated successfully');
        }

        return view('admin/edit_user', ['user' => $user]);
    }

    public function deleteUser($id)
    {
        $this->userModel->delete($id);
        return redirect()->to('/admin/users')->with('success', 'User deleted successfully');
    }

    public function projects()
    {
        $data['projects'] = $this->projectModel->select('projects.*, users.username, users.email')
            ->join('users', 'users.id = projects.user_id')
            ->findAll();

        return view('admin/projects', $data);
    }

    public function deleteProject($id)
    {
        $project = $this->projectModel->find($id);
        
        if ($project) {
            exec("rm -rf {$project['document_root']}");
            unlink("/etc/nginx/sites-enabled/{$project['subdomain']}");
            exec("systemctl reload nginx");
            
            $this->projectModel->delete($id);
        }

        return redirect()->to('/admin/projects')->with('success', 'Project deleted successfully');
    }
}
EOPHP

# Generate Models
print_status "Generating Models..."

cat > app/Models/UserModel.php << 'EOPHP'
<?php

namespace App\Models;

use CodeIgniter\Model;

class UserModel extends Model
{
    protected $table = 'users';
    protected $primaryKey = 'id';
    protected $allowedFields = [
        'username', 'email', 'password', 'full_name', 'role', 'status',
        'disk_quota', 'disk_used', 'bandwidth_quota', 'bandwidth_used', 'max_projects'
    ];
    protected $useTimestamps = true;
    protected $createdField = 'created_at';
    protected $updatedField = 'updated_at';

    protected $validationRules = [
        'username' => 'required|min_length[3]|max_length[50]|is_unique[users.username,id,{id}]',
        'email' => 'required|valid_email|is_unique[users.email,id,{id}]',
        'password' => 'required|min_length[6]'
    ];
}
EOPHP

cat > app/Models/ProjectModel.php << 'EOPHP'
<?php

namespace App\Models;

use CodeIgniter\Model;

class ProjectModel extends Model
{
    protected $table = 'projects';
    protected $primaryKey = 'id';
    protected $allowedFields = [
        'user_id', 'project_name', 'subdomain', 'full_domain', 'document_root',
        'php_version', 'ssl_enabled', 'ssl_cert_path', 'ssl_key_path', 'status',
        'disk_used', 'bandwidth_used', 'cloudflare_record_id'
    ];
    protected $useTimestamps = true;
    protected $createdField = 'created_at';
    protected $updatedField = 'updated_at';
}
EOPHP

# Generate Libraries
print_status "Generating Libraries..."

mkdir -p app/Libraries

cat > app/Libraries/CloudflareManager.php << 'EOPHP'
<?php

namespace App\Libraries;

class CloudflareManager
{
    private $apiToken;
    private $zoneId;
    private $mainDomain;

    public function __construct()
    {
        $this->apiToken = env('cloudflare.apiToken');
        $this->zoneId = env('cloudflare.zoneId');
        $this->mainDomain = env('cloudflare.mainDomain');
    }

    public function createDnsRecord($subdomain)
    {
        $url = "https://api.cloudflare.com/client/v4/zones/{$this->zoneId}/dns_records";
        
        $data = [
            'type' => 'A',
            'name' => $subdomain,
            'content' => $this->getServerIP(),
            'ttl' => 1,
            'proxied' => true
        ];

        $ch = curl_init($url);
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($ch, CURLOPT_POST, true);
        curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($data));
        curl_setopt($ch, CURLOPT_HTTPHEADER, [
            'Authorization: Bearer ' . $this->apiToken,
            'Content-Type: application/json'
        ]);

        $response = curl_exec($ch);
        curl_close($ch);

        $result = json_decode($response, true);

        return [
            'success' => $result['success'] ?? false,
            'record_id' => $result['result']['id'] ?? null
        ];
    }

    public function deleteDnsRecord($recordId)
    {
        if (!$recordId) return false;

        $url = "https://api.cloudflare.com/client/v4/zones/{$this->zoneId}/dns_records/{$recordId}";

        $ch = curl_init($url);
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($ch, CURLOPT_CUSTOMREQUEST, 'DELETE');
        curl_setopt($ch, CURLOPT_HTTPHEADER, [
            'Authorization: Bearer ' . $this->apiToken,
            'Content-Type: application/json'
        ]);

        $response = curl_exec($ch);
        curl_close($ch);

        return json_decode($response, true)['success'] ?? false;
    }

    private function getServerIP()
    {
        return trim(file_get_contents('https://api.ipify.org'));
    }
}
EOPHP

cat > app/Libraries/NginxManager.php << 'EOPHP'
<?php

namespace App\Libraries;

class NginxManager
{
    public function createVirtualHost($subdomain, $domain, $docRoot)
    {
        $config = "server {
    listen 80;
    listen [::]:80;
    server_name {$domain};
    root {$docRoot}/public;
    index index.php index.html;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php8.2-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ /\.ht {
        deny all;
    }
}";

        file_put_contents("/etc/nginx/sites-available/{$subdomain}", $config);
        symlink("/etc/nginx/sites-available/{$subdomain}", "/etc/nginx/sites-enabled/{$subdomain}");
        exec("nginx -t && systemctl reload nginx");
    }

    public function deleteVirtualHost($subdomain)
    {
        @unlink("/etc/nginx/sites-enabled/{$subdomain}");
        @unlink("/etc/nginx/sites-available/{$subdomain}");
        exec("systemctl reload nginx");
    }

    public function installSSL($domain)
    {
        exec("certbot --nginx -d {$domain} --non-interactive --agree-tos --email admin@{$domain} --redirect 2>&1", $output, $return);
        return $return === 0;
    }
}
EOPHP

# Generate Views
print_status "Generating Views..."

mkdir -p app/Views/{auth,dashboard,admin}

# Login View
cat > app/Views/auth/login.php << 'EOHTML'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Login - RizzDevs Panel</title>
    <script src="https://cdn.tailwindcss.com"></script>
</head>
<body class="bg-gradient-to-br from-blue-900 to-purple-900 min-h-screen flex items-center justify-center">
    <div class="bg-white rounded-lg shadow-2xl p-8 w-full max-w-md">
        <div class="text-center mb-8">
            <h1 class="text-3xl font-bold text-gray-800">RizzDevs Panel</h1>
            <p class="text-gray-600 mt-2">Sign in to your account</p>
        </div>

        <?php if(session()->getFlashdata('error')): ?>
            <div class="bg-red-100 border border-red-400 text-red-700 px-4 py-3 rounded mb-4">
                <?= session()->getFlashdata('error') ?>
            </div>
        <?php endif; ?>

        <?php if(session()->getFlashdata('success')): ?>
            <div class="bg-green-100 border border-green-400 text-green-700 px-4 py-3 rounded mb-4">
                <?= session()->getFlashdata('success') ?>
            </div>
        <?php endif; ?>

        <form method="post" action="/login">
            <div class="mb-4">
                <label class="block text-gray-700 text-sm font-bold mb-2">Email</label>
                <input type="email" name="email" required
                    class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:outline-none focus:border-blue-500">
            </div>

            <div class="mb-6">
                <label class="block text-gray-700 text-sm font-bold mb-2">Password</label>
                <input type="password" name="password" required
                    class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:outline-none focus:border-blue-500">
            </div>

            <button type="submit"
                class="w-full bg-blue-600 text-white font-bold py-3 px-4 rounded-lg hover:bg-blue-700 transition">
                Sign In
            </button>

            <div class="text-center mt-4">
                <a href="/register" class="text-blue-600 hover:text-blue-800">Don't have an account? Register</a>
            </div>
        </form>
    </div>
</body>
</html>
EOHTML

# Dashboard View
cat > app/Views/dashboard/index.php << 'EOHTML'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Dashboard - RizzDevs Panel</title>
    <script src="https://cdn.tailwindcss.com"></script>
</head>
<body class="bg-gray-100">
    <nav class="bg-white shadow-lg">
        <div class="max-w-7xl mx-auto px-4">
            <div class="flex justify-between items-center py-4">
                <div class="text-2xl font-bold text-blue-600">RizzDevs Panel</div>
                <div class="flex items-center space-x-4">
                    <span class="text-gray-700">Welcome, <?= session()->get('username') ?></span>
                    <a href="/logout" class="bg-red-500 text-white px-4 py-2 rounded hover:bg-red-600">Logout</a>
                </div>
            </div>
        </div>
    </nav>

    <div class="max-w-7xl mx-auto px-4 py-8">
        <div class="grid grid-cols-1 md:grid-cols-3 gap-6 mb-8">
            <div class="bg-white rounded-lg shadow p-6">
                <h3 class="text-gray-500 text-sm font-semibold">Total Projects</h3>
                <p class="text-3xl font-bold text-blue-600 mt-2"><?= count($projects) ?></p>
            </div>
            <div class="bg-white rounded-lg shadow p-6">
                <h3 class="text-gray-500 text-sm font-semibold">Disk Usage</h3>
                <p class="text-3xl font-bold text-green-600 mt-2"><?= round($user['disk_used'] / 1073741824, 2) ?> GB</p>
            </div>
            <div class="bg-white rounded-lg shadow p-6">
                <h3 class="text-gray-500 text-sm font-semibold">Bandwidth Used</h3>
                <p class="text-3xl font-bold text-purple-600 mt-2"><?= round($user['bandwidth_used'] / 1073741824, 2) ?> GB</p>
            </div>
        </div>

        <div class="bg-white rounded-lg shadow p-6">
            <div class="flex justify-between items-center mb-6">
                <h2 class="text-2xl font-bold text-gray-800">My Projects</h2>
                <a href="/dashboard/create-project" class="bg-blue-600 text-white px-6 py-2 rounded hover:bg-blue-700">
                    + New Project
                </a>
            </div>

            <?php if(count($projects) > 0): ?>
                <div class="overflow-x-auto">
                    <table class="w-full">
                        <thead class="bg-gray-50">
                            <tr>
                                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Project Name</th>
                                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Domain</th>
                                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">SSL</th>
                                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Status</th>
                                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Actions</th>
                            </tr>
                        </thead>
                        <tbody class="divide-y divide-gray-200">
                            <?php foreach($projects as $project): ?>
                            <tr>
                                <td class="px-6 py-4"><?= esc($project['project_name']) ?></td>
                                <td class="px-6 py-4">
                                    <a href="https://<?= esc($project['full_domain']) ?>" target="_blank" class="text-blue-600 hover:underline">
                                        <?= esc($project['full_domain']) ?>
                                    </a>
                                </td>
                                <td class="px-6 py-4">
                                    <?php if($project['ssl_enabled']): ?>
                                        <span class="bg-green-100 text-green-800 px-2 py-1 rounded text-xs">Enabled</span>
                                    <?php else: ?>
                                        <span class="bg-red-100 text-red-800 px-2 py-1 rounded text-xs">Disabled</span>
                                    <?php endif; ?>
                                </td>
                                <td class="px-6 py-4">
                                    <span class="bg-green-100 text-green-800 px-2 py-1 rounded text-xs"><?= ucfirst($project['status']) ?></span>
                                </td>
                                <td class="px-6 py-4">
                                    <a href="/dashboard/project/<?= $project['id'] ?>/delete" 
                                       onclick="return confirm('Are you sure?')"
                                       class="text-red-600 hover:text-red-800">Delete</a>
                                </td>
                            </tr>
                            <?php endforeach; ?>
                        </tbody>
                    </table>
                </div>
            <?php else: ?>
                <p class="text-gray-500 text-center py-8">No projects yet. Create your first project!</p>
            <?php endif; ?>
        </div>
    </div>
</body>
</html>
EOHTML

# Create Project View
cat > app/Views/dashboard/create_project.php << 'EOHTML'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Create Project - RizzDevs Panel</title>
    <script src="https://cdn.tailwindcss.com"></script>
</head>
<body class="bg-gray-100">
    <nav class="bg-white shadow-lg">
        <div class="max-w-7xl mx-auto px-4">
            <div class="flex justify-between items-center py-4">
                <div class="text-2xl font-bold text-blue-600">RizzDevs Panel</div>
                <div class="flex items-center space-x-4">
                    <a href="/dashboard" class="text-gray-700 hover:text-blue-600">Dashboard</a>
                    <a href="/logout" class="bg-red-500 text-white px-4 py-2 rounded hover:bg-red-600">Logout</a>
                </div>
            </div>
        </div>
    </nav>

    <div class="max-w-2xl mx-auto px-4 py-8">
        <div class="bg-white rounded-lg shadow p-8">
            <h2 class="text-2xl font-bold text-gray-800 mb-6">Create New Project</h2>

            <?php if(session()->getFlashdata('error')): ?>
                <div class="bg-red-100 border border-red-400 text-red-700 px-4 py-3 rounded mb-4">
                    <?= session()->getFlashdata('error') ?>
                </div>
            <?php endif; ?>

            <form method="post" action="/dashboard/create-project">
                <div class="mb-6">
                    <label class="block text-gray-700 text-sm font-bold mb-2">Project Name</label>
                    <input type="text" name="project_name" required
                        class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:outline-none focus:border-blue-500"
                        placeholder="e.g., airizz">
                    <p class="text-gray-500 text-xs mt-1">Your project will be accessible at: projectname.rizzdevs.biz.id</p>
                </div>

                <div class="flex items-center justify-between">
                    <a href="/dashboard" class="text-gray-600 hover:text-gray-800">← Back to Dashboard</a>
                    <button type="submit"
                        class="bg-blue-600 text-white font-bold py-2 px-6 rounded-lg hover:bg-blue-700 transition">
                        Create Project
                    </button>
                </div>
            </form>
        </div>
    </div>
</body>
</html>
EOHTML

# Admin Dashboard View
cat > app/Views/admin/dashboard.php << 'EOHTML'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Admin Dashboard - RizzDevs Panel</title>
    <script src="https://cdn.tailwindcss.com"></script>
</head>
<body class="bg-gray-100">
    <nav class="bg-blue-900 text-white shadow-lg">
        <div class="max-w-7xl mx-auto px-4">
            <div class="flex justify-between items-center py-4">
                <div class="text-2xl font-bold">RizzDevs Admin Panel</div>
                <div class="flex items-center space-x-6">
                    <a href="/admin/dashboard" class="hover:text-blue-200">Dashboard</a>
                    <a href="/admin/users" class="hover:text-blue-200">Users</a>
                    <a href="/admin/projects" class="hover:text-blue-200">Projects</a>
                    <a href="/logout" class="bg-red-500 px-4 py-2 rounded hover:bg-red-600">Logout</a>
                </div>
            </div>
        </div>
    </nav>

    <div class="max-w-7xl mx-auto px-4 py-8">
        <h1 class="text-3xl font-bold text-gray-800 mb-8">Admin Dashboard</h1>

        <div class="grid grid-cols-1 md:grid-cols-2 gap-6 mb-8">
            <div class="bg-white rounded-lg shadow p-6">
                <h3 class="text-gray-500 text-sm font-semibold">Total Users</h3>
                <p class="text-4xl font-bold text-blue-600 mt-2"><?= $total_users ?></p>
            </div>
            <div class="bg-white rounded-lg shadow p-6">
                <h3 class="text-gray-500 text-sm font-semibold">Total Projects</h3>
                <p class="text-4xl font-bold text-green-600 mt-2"><?= $total_projects ?></p>
            </div>
        </div>

        <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
            <div class="bg-white rounded-lg shadow p-6">
                <h2 class="text-xl font-bold text-gray-800 mb-4">Recent Users</h2>
                <div class="space-y-3">
                    <?php foreach($recent_users as $user): ?>
                        <div class="flex justify-between items-center border-b pb-2">
                            <div>
                                <p class="font-semibold"><?= esc($user['username']) ?></p>
                                <p class="text-sm text-gray-500"><?= esc($user['email']) ?></p>
                            </div>
                            <span class="text-xs text-gray-400"><?= date('M d, Y', strtotime($user['created_at'])) ?></span>
                        </div>
                    <?php endforeach; ?>
                </div>
            </div>

            <div class="bg-white rounded-lg shadow p-6">
                <h2 class="text-xl font-bold text-gray-800 mb-4">Recent Projects</h2>
                <div class="space-y-3">
                    <?php foreach($recent_projects as $project): ?>
                        <div class="flex justify-between items-center border-b pb-2">
                            <div>
                                <p class="font-semibold"><?= esc($project['project_name']) ?></p>
                                <p class="text-sm text-gray-500"><?= esc($project['full_domain']) ?></p>
                            </div>
                            <span class="text-xs text-gray-400"><?= date('M d, Y', strtotime($project['created_at'])) ?></span>
                        </div>
                    <?php endforeach; ?>
                </div>
            </div>
        </div>
    </div>
</body>
</html>
EOHTML

# Admin Users View
cat > app/Views/admin/users.php << 'EOHTML'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Manage Users - RizzDevs Panel</title>
    <script src="https://cdn.tailwindcss.com"></script>
</head>
<body class="bg-gray-100">
    <nav class="bg-blue-900 text-white shadow-lg">
        <div class="max-w-7xl mx-auto px-4">
            <div class="flex justify-between items-center py-4">
                <div class="text-2xl font-bold">RizzDevs Admin Panel</div>
                <div class="flex items-center space-x-6">
                    <a href="/admin/dashboard" class="hover:text-blue-200">Dashboard</a>
                    <a href="/admin/users" class="hover:text-blue-200 font-bold">Users</a>
                    <a href="/admin/projects" class="hover:text-blue-200">Projects</a>
                    <a href="/logout" class="bg-red-500 px-4 py-2 rounded hover:bg-red-600">Logout</a>
                </div>
            </div>
        </div>
    </nav>

    <div class="max-w-7xl mx-auto px-4 py-8">
        <div class="flex justify-between items-center mb-6">
            <h1 class="text-3xl font-bold text-gray-800">Manage Users</h1>
            <a href="/admin/users/create" class="bg-blue-600 text-white px-6 py-2 rounded hover:bg-blue-700">
                + Add User
            </a>
        </div>

        <?php if(session()->getFlashdata('success')): ?>
            <div class="bg-green-100 border border-green-400 text-green-700 px-4 py-3 rounded mb-4">
                <?= session()->getFlashdata('success') ?>
            </div>
        <?php endif; ?>

        <div class="bg-white rounded-lg shadow overflow-hidden">
            <table class="w-full">
                <thead class="bg-gray-50">
                    <tr>
                        <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Username</th>
                        <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Email</th>
                        <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Role</th>
                        <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Status</th>
                        <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Created</th>
                        <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Actions</th>
                    </tr>
                </thead>
                <tbody class="divide-y divide-gray-200">
                    <?php foreach($users as $user): ?>
                    <tr>
                        <td class="px-6 py-4"><?= esc($user['username']) ?></td>
                        <td class="px-6 py-4"><?= esc($user['email']) ?></td>
                        <td class="px-6 py-4">
                            <span class="bg-<?= $user['role'] === 'admin' ? 'red' : 'blue' ?>-100 text-<?= $user['role'] === 'admin' ? 'red' : 'blue' ?>-800 px-2 py-1 rounded text-xs">
                                <?= ucfirst($user['role']) ?>
                            </span>
                        </td>
                        <td class="px-6 py-4">
                            <span class="bg-green-100 text-green-800 px-2 py-1 rounded text-xs"><?= ucfirst($user['status']) ?></span>
                        </td>
                        <td class="px-6 py-4"><?= date('M d, Y', strtotime($user['created_at'])) ?></td>
                        <td class="px-6 py-4">
                            <a href="/admin/users/edit/<?= $user['id'] ?>" class="text-blue-600 hover:text-blue-800 mr-3">Edit</a>
                            <?php if($user['role'] !== 'admin'): ?>
                                <a href="/admin/users/delete/<?= $user['id'] ?>" 
                                   onclick="return confirm('Are you sure?')"
                                   class="text-red-600 hover:text-red-800">Delete</a>
                            <?php endif; ?>
                        </td>
                    </tr>
                    <?php endforeach; ?>
                </tbody>
            </table>
        </div>
    </div>
</body>
</html>
EOHTML

# Admin Create User View
cat > app/Views/admin/create_user.php << 'EOHTML'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Create User - RizzDevs Panel</title>
    <script src="https://cdn.tailwindcss.com"></script>
</head>
<body class="bg-gray-100">
    <nav class="bg-blue-900 text-white shadow-lg">
        <div class="max-w-7xl mx-auto px-4">
            <div class="flex justify-between items-center py-4">
                <div class="text-2xl font-bold">RizzDevs Admin Panel</div>
                <div class="flex items-center space-x-6">
                    <a href="/admin/dashboard" class="hover:text-blue-200">Dashboard</a>
                    <a href="/admin/users" class="hover:text-blue-200">Users</a>
                    <a href="/admin/projects" class="hover:text-blue-200">Projects</a>
                    <a href="/logout" class="bg-red-500 px-4 py-2 rounded hover:bg-red-600">Logout</a>
                </div>
            </div>
        </div>
    </nav>

    <div class="max-w-2xl mx-auto px-4 py-8">
        <div class="bg-white rounded-lg shadow p-8">
            <h2 class="text-2xl font-bold text-gray-800 mb-6">Create New User</h2>

            <form method="post" action="/admin/users/create">
                <div class="grid grid-cols-2 gap-4 mb-4">
                    <div>
                        <label class="block text-gray-700 text-sm font-bold mb-2">Username</label>
                        <input type="text" name="username" required
                            class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:outline-none focus:border-blue-500">
                    </div>
                    <div>
                        <label class="block text-gray-700 text-sm font-bold mb-2">Full Name</label>
                        <input type="text" name="full_name" required
                            class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:outline-none focus:border-blue-500">
                    </div>
                </div>

                <div class="mb-4">
                    <label class="block text-gray-700 text-sm font-bold mb-2">Email</label>
                    <input type="email" name="email" required
                        class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:outline-none focus:border-blue-500">
                </div>

                <div class="mb-4">
                    <label class="block text-gray-700 text-sm font-bold mb-2">Password</label>
                    <input type="password" name="password" required
                        class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:outline-none focus:border-blue-500">
                </div>

                <div class="grid grid-cols-2 gap-4 mb-4">
                    <div>
                        <label class="block text-gray-700 text-sm font-bold mb-2">Role</label>
                        <select name="role" required
                            class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:outline-none focus:border-blue-500">
                            <option value="user">User</option>
                            <option value="admin">Admin</option>
                        </select>
                    </div>
                    <div>
                        <label class="block text-gray-700 text-sm font-bold mb-2">Max Projects</label>
                        <input type="number" name="max_projects" value="10" required
                            class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:outline-none focus:border-blue-500">
                    </div>
                </div>

                <div class="mb-6">
                    <label class="block text-gray-700 text-sm font-bold mb-2">Disk Quota (GB)</label>
                    <input type="number" name="disk_quota" value="5" required
                        class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:outline-none focus:border-blue-500">
                </div>

                <div class="flex items-center justify-between">
                    <a href="/admin/users" class="text-gray-600 hover:text-gray-800">← Back to Users</a>
                    <button type="submit"
                        class="bg-blue-600 text-white font-bold py-2 px-6 rounded-lg hover:bg-blue-700 transition">
                        Create User
                    </button>
                </div>
            </form>
        </div>
    </div>
</body>
</html>
EOHTML

# Configure Routes
print_status "Configuring Routes..."

cat > app/Config/Routes.php << 'EOPHP'
<?php

use CodeIgniter\Router\RouteCollection;

/**
 * @var RouteCollection $routes
 */

// Auth Routes
$routes->get('/', 'Auth::login');
$routes->get('/login', 'Auth::login');
$routes->post('/login', 'Auth::login');
$routes->get('/register', 'Auth::register');
$routes->post('/register', 'Auth::register');
$routes->get('/logout', 'Auth::logout');

// User Dashboard Routes
$routes->group('dashboard', ['filter' => 'auth'], function($routes) {
    $routes->get('/', 'Dashboard::index');
    $routes->get('projects', 'Dashboard::projects');
    $routes->get('create-project', 'Dashboard::createProject');
    $routes->post('create-project', 'Dashboard::createProject');
    $routes->get('project/(:num)/delete', 'Dashboard::deleteProject/$1');
});

// Admin Routes
$routes->group('admin', ['filter' => 'auth:admin'], function($routes) {
    $routes->get('dashboard', 'Admin/Dashboard::index');
    
    $routes->get('users', 'Admin/Dashboard::users');
    $routes->get('users/create', 'Admin/Dashboard::createUser');
    $routes->post('users/create', 'Admin/Dashboard::createUser');
    $routes->get('users/edit/(:num)', 'Admin/Dashboard::editUser/$1');
    $routes->post('users/edit/(:num)', 'Admin/Dashboard::editUser/$1');
    $routes->get('users/delete/(:num)', 'Admin/Dashboard::deleteUser/$1');
    
    $routes->get('projects', 'Admin/Dashboard::projects');
    $routes->get('projects/delete/(:num)', 'Admin/Dashboard::deleteProject/$1');
});
EOPHP

# Create Auth Filter
print_status "Creating Auth Filter..."

mkdir -p app/Filters

cat > app/Filters/AuthFilter.php << 'EOPHP'
<?php

namespace App\Filters;

use CodeIgniter\HTTP\RequestInterface;
use CodeIgniter\HTTP\ResponseInterface;
use CodeIgniter\Filters\FilterInterface;

class AuthFilter implements FilterInterface
{
    public function before(RequestInterface $request, $arguments = null)
    {
        if (!session()->get('logged_in')) {
            return redirect()->to('/login');
        }

        if ($arguments && in_array('admin', $arguments)) {
            if (session()->get('role') !== 'admin') {
                return redirect()->to('/dashboard')->with('error', 'Access denied');
            }
        }
    }

    public function after(RequestInterface $request, ResponseInterface $response, $arguments = null)
    {
        //
    }
}
EOPHP

# Register Filter
cat >> app/Config/Filters.php << 'EOPHP'

public $aliases = [
    'csrf'     => \CodeIgniter\Filters\CSRF::class,
    'toolbar'  => \CodeIgniter\Filters\DebugToolbar::class,
    'honeypot' => \CodeIgniter\Filters\Honeypot::class,
    'auth'     => \App\Filters\AuthFilter::class,
];
EOPHP

# Set permissions
print_status "Setting permissions..."
chown -R www-data:www-data ${PANEL_DIR}
chmod -R 755 ${PANEL_DIR}
chmod -R 775 ${PANEL_DIR}/writable

# Configure main domain nginx
print_status "Configuring main domain nginx..."

cat > /etc/nginx/sites-available/rizzdevs-panel << EONGINX
server {
    listen 80;
    listen [::]:80;
    server_name ${MAIN_DOMAIN} ${ADMIN_SUBDOMAIN};
    root ${PANEL_DIR}/public;
    index index.php index.html;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php8.2-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ /\.ht {
        deny all;
    }
}
EONGINX

ln -sf /etc/nginx/sites-available/rizzdevs-panel /etc/nginx/sites-enabled/
nginx -t && systemctl reload nginx

# Setup CloudFlare SSL
print_status "Installing SSL certificates..."

mkdir -p /root/.secrets/certbot
cat > /root/.secrets/certbot/cloudflare.ini << EOCF
dns_cloudflare_api_token = ${CLOUDFLARE_API_TOKEN}
EOCF

chmod 600 /root/.secrets/certbot/cloudflare.ini

certbot certonly \
    --dns-cloudflare \
    --dns-cloudflare-credentials /root/.secrets/certbot/cloudflare.ini \
    -d ${MAIN_DOMAIN} \
    -d ${ADMIN_SUBDOMAIN} \
    -d "*.${MAIN_DOMAIN}" \
    --non-interactive \
    --agree-tos \
    --email ${ADMIN_EMAIL}

# Update nginx with SSL
cat > /etc/nginx/sites-available/rizzdevs-panel << EONGINX
server {
    listen 80;
    listen [::]:80;
    server_name ${MAIN_DOMAIN} ${ADMIN_SUBDOMAIN};
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name ${MAIN_DOMAIN} ${ADMIN_SUBDOMAIN};
    
    ssl_certificate /etc/letsencrypt/live/${MAIN_DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${MAIN_DOMAIN}/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    root ${PANEL_DIR}/public;
    index index.php index.html;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php8.2-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ /\.ht {
        deny all;
    }
}
EONGINX

systemctl reload nginx

# Create projects directory
mkdir -p /var/www/projects
chown -R www-data:www-data /var/www/projects

# Setup auto-renewal
print_status "Setting up SSL auto-renewal..."
(crontab -l 2>/dev/null; echo "0 0,12 * * * certbot renew --quiet") | crontab -

# Create installation info file
cat > ${PANEL_DIR}/INSTALLATION_INFO.txt << EOINFO
╔═══════════════════════════════════════════════════════════╗
║        RizzDevs Hosting Panel Installation Complete      ║
╚═══════════════════════════════════════════════════════════╝

Installation completed successfully!

PANEL ACCESS INFORMATION:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Main Panel URL:     https://${MAIN_DOMAIN}
Admin Panel URL:    https://${ADMIN_SUBDOMAIN}

ADMIN CREDENTIALS:
Email:    ${ADMIN_EMAIL}
Password: ${ADMIN_PASS}

DATABASE INFORMATION:
Database Name: ${DB_NAME}
Database User: ${DB_USER}
Database Pass: ${DB_PASS}

CLOUDFLARE:
API Token: ${CLOUDFLARE_API_TOKEN}
Zone ID:   ${CLOUDFLARE_ZONE_ID}

FEATURES INSTALLED:
✓ Nginx Web Server
✓ PHP 8.2-FPM
✓ MariaDB Database
✓ CodeIgniter 4 Framework
✓ SSL/TLS Certificates (Let's Encrypt + CloudFlare)
✓ Auto DNS Management (CloudFlare API)
✓ User & Admin Dashboard
✓ Project Management System
✓ Auto Subdomain Creation
✓ Automatic SSL for subdomains

SYSTEM PATHS:
Panel Directory:    ${PANEL_DIR}
Projects Directory: /var/www/projects
Nginx Config:       /etc/nginx/sites-available/
SSL Certificates:   /etc/letsencrypt/live/

NEXT STEPS:
1. Login to admin panel: https://${ADMIN_SUBDOMAIN}
2. Create new users or use existing admin account
3. Create projects - subdomains will be automatically generated
4. Each project gets its own subdomain with SSL

IMPORTANT SECURITY NOTES:
⚠ Change the admin password immediately after first login
⚠ Keep this file secure - it contains sensitive credentials
⚠ Backup your database regularly
⚠ Keep CloudFlare API token secure

For support: https://rizzdevs.biz.id
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOINFO

chmod 600 ${PANEL_DIR}/INSTALLATION_INFO.txt

# Create maintenance scripts
print_status "Creating maintenance scripts..."

cat > /usr/local/bin/rizzdevs-backup << 'EOBACKUP'
#!/bin/bash
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/backups/rizzdevs"
mkdir -p ${BACKUP_DIR}

echo "Creating backup..."
mysqldump -u ${DB_USER} -p${DB_PASS} ${DB_NAME} > ${BACKUP_DIR}/db_${DATE}.sql
tar -czf ${BACKUP_DIR}/files_${DATE}.tar.gz /var/www/rizzdevs-panel /var/www/projects

echo "Backup completed: ${BACKUP_DIR}"
find ${BACKUP_DIR} -type f -mtime +7 -delete
EOBACKUP

chmod +x /usr/local/bin/rizzdevs-backup

# Create project cleanup script
cat > /usr/local/bin/rizzdevs-cleanup << 'EOCLEANUP'
#!/bin/bash
# Clean old logs and temp files
find /var/www/projects -type f -name "*.log" -mtime +30 -delete
find /var/www/rizzdevs-panel/writable/logs -type f -mtime +30 -delete
echo "Cleanup completed"
EOCLEANUP

chmod +x /usr/local/bin/rizzdevs-cleanup

# Setup cron jobs
print_status "Setting up automated tasks..."
(crontab -l 2>/dev/null; echo "0 2 * * * /usr/local/bin/rizzdevs-backup") | crontab -
(crontab -l 2>/dev/null; echo "0 3 * * 0 /usr/local/bin/rizzdevs-cleanup") | crontab -

# Create update script
cat > /usr/local/bin/rizzdevs-update << 'EOUPDATE'
#!/bin/bash
echo "Updating RizzDevs Panel..."
cd /var/www/rizzdevs-panel
composer update --no-interaction
php spark migrate
php spark cache:clear
systemctl reload nginx php8.2-fpm
echo "Update completed!"
EOUPDATE

chmod +x /usr/local/bin/rizzdevs-update

# Enable services
print_status "Enabling services..."
systemctl enable nginx
systemctl enable mariadb
systemctl enable php8.2-fpm

# Final check
print_status "Running final checks..."
nginx -t
systemctl status nginx --no-pager
systemctl status mariadb --no-pager
systemctl status php8.2-fpm --no-pager

# Create admin register view (missing from earlier)
cat > app/Views/auth/register.php << 'EOHTML'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Register - RizzDevs Panel</title>
    <script src="https://cdn.tailwindcss.com"></script>
</head>
<body class="bg-gradient-to-br from-blue-900 to-purple-900 min-h-screen flex items-center justify-center">
    <div class="bg-white rounded-lg shadow-2xl p-8 w-full max-w-md">
        <div class="text-center mb-8">
            <h1 class="text-3xl font-bold text-gray-800">Create Account</h1>
            <p class="text-gray-600 mt-2">Join RizzDevs Panel</p>
        </div>

        <?php if(session()->getFlashdata('error')): ?>
            <div class="bg-red-100 border border-red-400 text-red-700 px-4 py-3 rounded mb-4">
                <?= session()->getFlashdata('error') ?>
            </div>
        <?php endif; ?>

        <form method="post" action="/register">
            <div class="mb-4">
                <label class="block text-gray-700 text-sm font-bold mb-2">Username</label>
                <input type="text" name="username" required
                    class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:outline-none focus:border-blue-500">
            </div>

            <div class="mb-4">
                <label class="block text-gray-700 text-sm font-bold mb-2">Full Name</label>
                <input type="text" name="full_name" required
                    class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:outline-none focus:border-blue-500">
            </div>

            <div class="mb-4">
                <label class="block text-gray-700 text-sm font-bold mb-2">Email</label>
                <input type="email" name="email" required
                    class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:outline-none focus:border-blue-500">
            </div>

            <div class="mb-6">
                <label class="block text-gray-700 text-sm font-bold mb-2">Password</label>
                <input type="password" name="password" required
                    class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:outline-none focus:border-blue-500">
            </div>

            <button type="submit"
                class="w-full bg-blue-600 text-white font-bold py-3 px-4 rounded-lg hover:bg-blue-700 transition">
                Create Account
            </button>

            <div class="text-center mt-4">
                <a href="/login" class="text-blue-600 hover:text-blue-800">Already have an account? Login</a>
            </div>
        </form>
    </div>
</body>
</html>
EOHTML

# Create admin projects view
cat > app/Views/admin/projects.php << 'EOHTML'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Manage Projects - RizzDevs Panel</title>
    <script src="https://cdn.tailwindcss.com"></script>
</head>
<body class="bg-gray-100">
    <nav class="bg-blue-900 text-white shadow-lg">
        <div class="max-w-7xl mx-auto px-4">
            <div class="flex justify-between items-center py-4">
                <div class="text-2xl font-bold">RizzDevs Admin Panel</div>
                <div class="flex items-center space-x-6">
                    <a href="/admin/dashboard" class="hover:text-blue-200">Dashboard</a>
                    <a href="/admin/users" class="hover:text-blue-200">Users</a>
                    <a href="/admin/projects" class="hover:text-blue-200 font-bold">Projects</a>
                    <a href="/logout" class="bg-red-500 px-4 py-2 rounded hover:bg-red-600">Logout</a>
                </div>
            </div>
        </div>
    </nav>

    <div class="max-w-7xl mx-auto px-4 py-8">
        <h1 class="text-3xl font-bold text-gray-800 mb-6">All Projects</h1>

        <?php if(session()->getFlashdata('success')): ?>
            <div class="bg-green-100 border border-green-400 text-green-700 px-4 py-3 rounded mb-4">
                <?= session()->getFlashdata('success') ?>
            </div>
        <?php endif; ?>

        <div class="bg-white rounded-lg shadow overflow-hidden">
            <table class="w-full">
                <thead class="bg-gray-50">
                    <tr>
                        <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Project</th>
                        <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Owner</th>
                        <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Domain</th>
                        <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">SSL</th>
                        <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Status</th>
                        <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Created</th>
                        <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Actions</th>
                    </tr>
                </thead>
                <tbody class="divide-y divide-gray-200">
                    <?php foreach($projects as $project): ?>
                    <tr>
                        <td class="px-6 py-4"><?= esc($project['project_name']) ?></td>
                        <td class="px-6 py-4">
                            <div>
                                <p class="font-semibold"><?= esc($project['username']) ?></p>
                                <p class="text-xs text-gray-500"><?= esc($project['email']) ?></p>
                            </div>
                        </td>
                        <td class="px-6 py-4">
                            <a href="https://<?= esc($project['full_domain']) ?>" target="_blank" class="text-blue-600 hover:underline">
                                <?= esc($project['full_domain']) ?>
                            </a>
                        </td>
                        <td class="px-6 py-4">
                            <span class="bg-green-100 text-green-800 px-2 py-1 rounded text-xs">
                                <?= $project['ssl_enabled'] ? 'Enabled' : 'Disabled' ?>
                            </span>
                        </td>
                        <td class="px-6 py-4">
                            <span class="bg-green-100 text-green-800 px-2 py-1 rounded text-xs"><?= ucfirst($project['status']) ?></span>
                        </td>
                        <td class="px-6 py-4"><?= date('M d, Y', strtotime($project['created_at'])) ?></td>
                        <td class="px-6 py-4">
                            <a href="/admin/projects/delete/<?= $project['id'] ?>" 
                               onclick="return confirm('This will delete the project and all its files. Continue?')"
                               class="text-red-600 hover:text-red-800">Delete</a>
                        </td>
                    </tr>
                    <?php endforeach; ?>
                </tbody>
            </table>
        </div>
    </div>
</body>
</html>
EOHTML

# Create BaseController with auth check
cat > app/Controllers/BaseController.php << 'EOPHP'
<?php

namespace App\Controllers;

use CodeIgniter\Controller;
use CodeIgniter\HTTP\CLIRequest;
use CodeIgniter\HTTP\IncomingRequest;
use CodeIgniter\HTTP\RequestInterface;
use CodeIgniter\HTTP\ResponseInterface;
use Psr\Log\LoggerInterface;

abstract class BaseController extends Controller
{
    protected $request;
    protected $helpers = ['url', 'form'];

    public function initController(RequestInterface $request, ResponseInterface $response, LoggerInterface $logger)
    {
        parent::initController($request, $response, $logger);
    }
}
EOPHP

# Display completion message
clear

cat << 'EOF'

╔════════════════════════════════════════════════════════════════╗
║                                                                ║
║     ██████╗ ██╗███████╗███████╗██████╗ ███████╗██╗   ██╗███████╗
║     ██╔══██╗██║╚══███╔╝╚══███╔╝██╔══██╗██╔════╝██║   ██║██╔════╝
║     ██████╔╝██║  ███╔╝   ███╔╝ ██║  ██║█████╗  ██║   ██║███████╗
║     ██╔══██╗██║ ███╔╝   ███╔╝  ██║  ██║██╔══╝  ╚██╗ ██╔╝╚════██║
║     ██║  ██║██║███████╗███████╗██████╔╝███████╗ ╚████╔╝ ███████║
║     ╚═╝  ╚═╝╚═╝╚══════╝╚══════╝╚═════╝ ╚══════╝  ╚═══╝  ╚══════╝
║                                                                ║
║               HOSTING PANEL INSTALLATION COMPLETE!            ║
║                                                                ║
╚════════════════════════════════════════════════════════════════╝

EOF

echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║          Installation completed successfully!             ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}Panel Access Information:${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}Main Panel URL:${NC}     https://${MAIN_DOMAIN}"
echo -e "${GREEN}Admin Panel URL:${NC}    https://${ADMIN_SUBDOMAIN}"
echo ""
echo -e "${BLUE}Admin Credentials:${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}Email:${NC}    ${ADMIN_EMAIL}"
echo -e "${GREEN}Password:${NC} ${ADMIN_PASS}"
echo ""
echo -e "${BLUE}Database Information:${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}Database:${NC} ${DB_NAME}"
echo -e "${GREEN}User:${NC}     ${DB_USER}"
echo -e "${GREEN}Password:${NC} ${DB_PASS}"
echo ""
echo -e "${BLUE}Features Installed:${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✓${NC} Nginx Web Server with PHP 8.2-FPM"
echo -e "${GREEN}✓${NC} MariaDB Database Server"
echo -e "${GREEN}✓${NC} CodeIgniter 4 Framework (Auto-Generated)"
echo -e "${GREEN}✓${NC} SSL/TLS Certificates (Let's Encrypt + CloudFlare)"
echo -e "${GREEN}✓${NC} CloudFlare DNS Integration"
echo -e "${GREEN}✓${NC} User & Admin Dashboard (Full CRUD)"
echo -e "${GREEN}✓${NC} Automatic Subdomain Creation"
echo -e "${GREEN}✓${NC} Automatic SSL for Each Project"
echo -e "${GREEN}✓${NC} Project Management System"
echo ""
echo -e "${BLUE}Useful Commands:${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}Backup:${NC}  rizzdevs-backup"
echo -e "${GREEN}Cleanup:${NC} rizzdevs-cleanup"
echo -e "${GREEN}Update:${NC}  rizzdevs-update"
echo ""
echo -e "${RED}⚠ IMPORTANT SECURITY NOTES:${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}1.${NC} Change admin password after first login"
echo -e "${YELLOW}2.${NC} Installation details saved to: ${PANEL_DIR}/INSTALLATION_INFO.txt"
echo -e "${YELLOW}3.${NC} Keep CloudFlare API credentials secure"
echo -e "${YELLOW}4.${NC} Backup database regularly (automated daily at 2 AM)"
echo ""
echo -e "${GREEN}Next Steps:${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "1. Visit: ${GREEN}https://${ADMIN_SUBDOMAIN}${NC}"
echo -e "2. Login with credentials above"
echo -e "3. Change admin password immediately"
echo -e "4. Create users and projects"
echo -e "5. Each project gets automatic subdomain with SSL"
echo ""
echo -e "${BLUE}Example: Create project 'airizz' → Access at airizz.${MAIN_DOMAIN}${NC}"
echo ""
echo -e "${GREEN}Installation log: /var/log/rizzdevs-install.log${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

print_status "Installation complete! Access your panel at https://${MAIN_DOMAIN}"

exit 0