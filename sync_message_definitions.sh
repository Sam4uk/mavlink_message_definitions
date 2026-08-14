#!/bin/bash

# Зупинити скрипт у разі виникнення помилки
set -e

# ==========================================
# Значення за замовчуванням
# ==========================================
EXT_OWNER="mavlink"
EXT_REPO="mavlink"
BRANCH="master"
STATE_FILE=".last_ext_commit"
INTERNAL_DIR="./"
EXTERNAL_DIR="external-source-code"

# ==========================================
# Обробка аргументів командного рядка
# ==========================================
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -o|--owner) EXT_OWNER="$2"; shift ;;
        -r|--repo) EXT_REPO="$2"; shift ;;
        -b|--branch) BRANCH="$2"; shift ;;
        -h|--help) 
            echo "Використання: ./sync_mavlink.sh [ПАРАМЕТРИ]"
            echo "Параметри:"
            echo "  -o, --owner   Власник репозиторію (за замовчуванням: $EXT_OWNER)"
            echo "  -r, --repo    Назва репозиторію (за замовчуванням: $EXT_REPO)"
            echo "  -b, --branch  Гілка (за замовчуванням: $BRANCH)"
            echo "  -h, --help    Показати цю довідку"
            exit 0
            ;;
        *) 
            echo "❌ Невідомий параметр: $1"
            echo "Використовуйте ./sync_mavlink.sh --help для довідки."
            exit 1 
            ;;
    esac
    shift
done

echo "⚙️  Налаштування синхронізації:"
echo "Власник: $EXT_OWNER | Репо: $EXT_REPO | Гілка: $BRANCH"
echo "---------------------------------------------------"

echo "1. Отримання останнього коміту з GitHub API..."
API_URL="https://api.github.com/repos/$EXT_OWNER/$EXT_REPO/commits/$BRANCH"
# Використовуємо curl для запиту і jq для парсингу JSON
LATEST_COMMIT=$(curl -s "$API_URL" | jq -r '.sha')

if [ "$LATEST_COMMIT" == "null" ] || [ -z "$LATEST_COMMIT" ]; then
    echo "❌ Помилка отримання даних з API."
    exit 1
fi

echo "Останній коміт: $LATEST_COMMIT"

# ==========================================
# Порівняння зі збереженим станом
# ==========================================
echo "2. Порівняння зі збереженим станом..."
SAVED_COMMIT="none"

if [ -f "$STATE_FILE" ]; then
    SAVED_COMMIT=$(cat "$STATE_FILE")
fi

if [ "$LATEST_COMMIT" == "$SAVED_COMMIT" ]; then
    echo "✅ Нових комітів немає. Зупинка скрипту."
    exit 0
fi

echo "Знайдено новий коміт! Продовжуємо оновлення."

# ==========================================
# Завантаження стороннього репозиторію
# ==========================================
echo "3. Завантаження репозиторію $EXT_OWNER/$EXT_REPO..."
# Використовуємо --depth 1, щоб завантажити лише останній стан і зекономити час/трафік
git clone --depth 1 --branch "$BRANCH" "https://github.com/$EXT_OWNER/$EXT_REPO.git" "$EXTERNAL_DIR"

# ==========================================
# Копіювання XML файлів
# ==========================================
echo "4. Пошук та копіювання XML-файлів..."
mkdir -p "$INTERNAL_DIR"
find "./$EXTERNAL_DIR/message_definitions" -type f -name "*.xml" -exec cp {} "./$INTERNAL_DIR/" \;

# ==========================================
# Очищення та Коміт
# ==========================================
echo "5. Очищення тимчасових файлів..."
rm -rf "$EXTERNAL_DIR"

# Оновлюємо файл стану
echo "$LATEST_COMMIT" > "$STATE_FILE"

echo "6. Підготовка коміту..."
# Якщо ви запускаєте це локально, ваші глобальні налаштування Git вже застосовані.
# Наступні два рядки потрібні лише якщо скрипт працюватиме як бот на сервері:
# git config user.name "your-bot-name"
# git config user.email "your-bot-email@example.com"

git add .

# Перевіряємо, чи є зміни для коміту
if git diff --staged --quiet; then
    echo "XML файли не змінились. Комічу лише $STATE_FILE"
    git commit -m "Оновлено індекс коміту: $LATEST_COMMIT"
else
    echo "Зміни знайдено. Створення коміту."
    git commit -m "Оновлено XML файли MAVLink. Коміт: $LATEST_COMMIT"
fi

echo "7. Відправка змін на сервер..."
# Налаштовуємо авторизацію Git за допомогою токена
# Для GitHub (використовує token для авторизації):
if [ -n "$GITHUB_ACTIONS" ]; then
    git remote set-url origin "https://x-access-token:${GITLAB_TOKEN}@github.com/${CI_PROJECT_PATH}.git"
elif [ -n "$GITLAB_CI" ]; then
    git remote set-url origin "https://oauth2:${GITLAB_TOKEN}@gitlab.com/${CI_PROJECT_PATH}.git"
fi
# Відправляємо поточний стан у ту ж гілку, з якої запустилися
if [ -n "$CI_COMMIT_BRANCH" ]; then
    git push origin HEAD:"$CI_COMMIT_BRANCH"
else
    git push origin HEAD:main
fi

echo "🎉 Синхронізація успішно завершена!"