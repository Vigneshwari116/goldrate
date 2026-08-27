# Deploy API to Hostinger VPS

Your VPS details:
- **IP:** `187.127.180.135`
- **SSH:** `ssh root@187.127.180.135`
- **OS:** Ubuntu 24.04

## Step 1 — Open Hostinger Terminal

In Hostinger panel click **Terminal** (top right), or SSH from your PC:

```bash
ssh root@187.127.180.135
```

## Step 2 — Check PostgreSQL is running

```bash
sudo systemctl status postgresql
sudo -u postgres psql -c "\l"
```

If PostgreSQL is not installed:

```bash
sudo apt update
sudo apt install postgresql postgresql-contrib -y
```

## Step 3 — Create database and user

```bash
sudo -u postgres psql
```

Inside psql:

```sql
CREATE USER jewellery_user WITH PASSWORD 'YourStrongPassword123';
CREATE DATABASE jewellery_db OWNER jewellery_user;
\q
```

## Step 4 — Create tables

Upload `schema.sql` to the VPS, then run:

```bash
sudo -u postgres psql -d jewellery_db -f schema.sql
```

Or paste the SQL from `schema.sql` manually in psql.

## Step 5 — Deploy API (choose one)

### Option A — Docker (recommended, no Node.js install needed)

Install Docker on VPS (one time):

```bash
curl -fsSL https://get.docker.com | sh
```

Upload code from your PC:

```bash
scp -r server root@187.127.180.135:/root/jewellery-api
```

On VPS, edit `docker-compose.yml` and set your real password in `DATABASE_URL`, then:

```bash
cd /root/jewellery-api
docker compose up -d --build
docker compose logs -f
```

To restart after changes:

```bash
docker compose down
docker compose up -d --build
```

### Option B — Node.js directly (without Docker)

Upload `server` folder from your PC:

```bash
scp -r server root@187.127.180.135:/root/jewellery-api
```

On the VPS:

```bash
cd /root/jewellery-api
cp .env.example .env
nano .env
```

Set:

```env
PORT=3000
DATABASE_URL=postgresql://jewellery_user:YourStrongPassword123@localhost:5432/jewellery_db
```

Install and start:

```bash
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt install -y nodejs
npm install
npm install -g pm2
pm2 start index.js --name jewellery-api
pm2 save
pm2 startup
```

## Step 6 — Open firewall port 3000

In Hostinger panel → **Security** → **Firewall**, allow port **3000** (TCP).

Or on VPS:

```bash
sudo ufw allow 3000/tcp
sudo ufw enable
```

## Step 7 — Test API

```bash
curl http://187.127.180.135:3000/api/health
```

Expected:

```json
{"ok":true,"db":"connected"}
```

Test login:

```bash
curl -X POST http://187.127.180.135:3000/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"ADMIN","password":"SVENSKA"}'
```

## Step 8 — Connect Flutter app

In `lib/config/api_config.dart` set:

```dart
static const String baseUrl = 'http://187.127.180.135:3000/api';
```

Rebuild the app. Customer save will go to PostgreSQL on your VPS.

## Important security notes

- Do **not** expose PostgreSQL port 5432 to the internet — only the API (port 3000) should be public.
- Change the default `ADMIN` / `SVENSKA` password in production.
- Later add HTTPS with a domain + Let's Encrypt (recommended before going live).
