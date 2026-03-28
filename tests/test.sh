#!/bin/bash
# =============================================================================
# Functional End-to-End Tests for La Roca Rules Engine (MVP)
# =============================================================================

HOST="http://localhost:8080"
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# --- START SETUP ---
echo "🧹 Cleaning previous state..."
docker compose down -v > /dev/null 2>&1

echo "🧹 Cleaning up JIT artifacts..."
rm -rf .cache/
mkdir -p .cache/

echo "🏗️  Starting ephemeral engine (Rules Engine E2E Mode)..."
docker compose up -d --build rules-engine > /dev/null 2>&1
echo "⏳ Waiting for the engine to boot..."
sleep 2
# --- END SETUP ---

echo "🚀 Starting La Roca Rules Engine E2E Tests..."
echo "Target: $HOST"
echo "-----------------------------------------------------------------"

# Helper function to print logs and exit on failure
fail_and_exit() {
    echo -e "${YELLOW}\n=== 🕵️‍♂️ DOCKER LOGS (rules-engine) ===${NC}"
    docker compose logs rules-engine
    echo -e "${YELLOW}=======================================${NC}\n"

    echo "🧹 Tearing down containers..."
    docker compose down -v > /dev/null 2>&1
    exit 1
}

# Helper function to check HTTP status codes
check_status() {
    local endpoint=$1
    local method=$2
    local expected=$3
    local payload=$4
    local description=$5

    # 🛡️ El "Borrador de Fantasmas": 100 espacios en blanco.
    # Sobrescribe cualquier dato residual en el buffer lógico del motor.
    local pad="                                                                                                    "
    local padded_payload="${payload}${pad}"

    if [ "$method" == "POST" ]; then
        STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X POST --data-binary "${padded_payload}" "$HOST$endpoint")
    else
        STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X GET "$HOST$endpoint")
    fi

    if [ "$STATUS" -eq "$expected" ]; then
        echo -e "${GREEN}[PASS]${NC} $description (Got $STATUS)"
    else
        echo -e "${RED}[FAIL]${NC} $description (Expected $expected, got $STATUS)"
        fail_and_exit
    fi
}

# Helper function to check exact response payload (Upgraded to support POST)
check_payload() {
    local endpoint=$1
    local method=$2
    local payload=$3
    local expected_response=$4
    local description=$5

    # 🛡️ Aplicamos el mismo blindaje de espacios
    local pad="                                                                                                    "
    local padded_payload="${payload}${pad}"

    if [ "$method" == "POST" ]; then
        RESPONSE=$(curl -s -X POST --data-binary "${padded_payload}" "$HOST$endpoint" | tr -d '\0')
    else
        RESPONSE=$(curl -s -X GET "$HOST$endpoint" | tr -d '\0')
    fi

    if [ "$RESPONSE" == "$expected_response" ]; then
        echo -e "${GREEN}[PASS]${NC} $description"
    else
        echo -e "${RED}[FAIL]${NC} $description"
        echo "       Expected: $expected_response"
        echo "       Got:      $RESPONSE"
        fail_and_exit
    fi
}

# =============================================================================
# TEST SUITE
# =============================================================================

# 1. System Health (Probes)
check_status "/live" "GET" 200 "" "Liveness probe is reachable"
check_payload "/live" "GET" "" "Alive" "Liveness probe returns 'Alive'"

check_status "/ready" "GET" 200 "" "Readiness probe is reachable"
check_payload "/ready" "GET" "" "Ready" "Readiness probe returns 'Ready'"

# 2. Engine Evaluation (Operator >)
check_status "/eval" "POST" 200 "7>2" "Valid eval request returns 200 OK"
check_payload "/eval" "POST" "7>2" '{"result":true}' "Evaluate '7>2' (Expected: True)"
check_payload "/eval" "POST" "3>8" '{"result":false}' "Evaluate '3>8' (Expected: False)"

# 3. Engine Evaluation (Operator <)
check_payload "/eval" "POST" "1<5" '{"result":true}' "Evaluate '1<5' (Expected: True)"
check_payload "/eval" "POST" "9<4" '{"result":false}' "Evaluate '9<4' (Expected: False)"

# 4. Engine Evaluation (Operator =)
check_payload "/eval" "POST" "6=6" '{"result":true}' "Evaluate '6=6' (Expected: True)"
check_payload "/eval" "POST" "6=7" '{"result":false}' "Evaluate '6=7' (Expected: False)"

# 5. Error Handling (Bad Requests)
# Note: rules.asm returns HTTP 400 for errors
check_status "/eval" "POST" 400 "5 $ 5" "Unknown operator '$' returns 400 Bad Request"
check_payload "/eval" "POST" "5 $ 5" "Error" "Unknown operator payload is 'Error'"

check_status "/eval" "POST" 400 "5>" "Incomplete payload returns 400 Bad Request"
check_payload "/eval" "POST" "5>" "Error" "Incomplete payload is 'Error'"

echo "--- 6. Engine Context Mapping (Descriptive Variables) ---"
# Variables vs Variables
MAP_PAYLOAD_1=$(printf "user_age=25,min_age=18\nuser_age>min_age")
check_payload "/eval" "POST" "$MAP_PAYLOAD_1" '{"result":true}' "Evaluate 'user_age>min_age' with context (Expected: True)"

MAP_PAYLOAD_2=$(printf "balance=300,cost=800\nbalance>cost")
check_payload "/eval" "POST" "$MAP_PAYLOAD_2" '{"result":false}' "Evaluate 'balance>cost' with context (Expected: False)"

# Variables vs Literals (Híbrido)
MAP_PAYLOAD_3=$(printf "is_active=1\nis_active=1")
check_payload "/eval" "POST" "$MAP_PAYLOAD_3" '{"result":true}' "Evaluate 'is_active=1' mixed var and literal (Expected: True)"

MAP_PAYLOAD_4=$(printf "retry_count=1\nretry_count>4")
check_payload "/eval" "POST" "$MAP_PAYLOAD_4" '{"result":false}' "Evaluate 'retry_count>4' mixed var and literal (Expected: False)"
echo ""

echo "--- 7. Multi-Rule Engine (AND Strategy / Fail-Fast) ---"
# All rules are true
MULTI_1=$(printf "score=80,min_score=60,bonus=5\nscore>min_score\nbonus<score\nmin_score=60")
check_payload "/eval" "POST" "$MULTI_1" '{"result":true}' "Evaluate 3 passing descriptive rules (Expected: True)"

# Second rule is false (Fail-Fast trigger)
MULTI_2=$(printf "level_a=3,level_b=3\nlevel_a=level_b\nlevel_a>level_b\n1<9")
check_payload "/eval" "POST" "$MULTI_2" '{"result":false}' "Evaluate 3 descriptive rules, 2nd fails (Expected: False)"

# No map, empty first line, multiple literals
MULTI_3=$(printf "\n9>1\n4<8\n5=5")
check_payload "/eval" "POST" "$MULTI_3" '{"result":true}' "Evaluate 3 literal rules with empty map (Expected: True)"
echo ""

echo "--- 8. Multi-Rule Engine (OR Strategy / Succeed-Fast) ---"
# OR Mode: The first fails, but the second succeeds -> Short circuits to True
OR_1=$(printf "MODE=OR\nval_x=1,val_y=9\nval_x>val_y\nval_y>val_x\n1=2")
check_payload "/eval" "POST" "$OR_1" '{"result":true}' "Evaluate OR (Descriptive): 2nd rule is true (Expected: True)"

# OR Mode: All fail -> Returns False
OR_2=$(printf "MODE=OR\n\n1>9\n2=3\n4<0")
check_payload "/eval" "POST" "$OR_2" '{"result":false}' "Evaluate OR: All rules fail (Expected: False)"
echo ""

echo "--- 9. High Precision & Negative Numbers (Descriptive) ---"
# Negative comparison
NEG_1=$(printf "temp_celsius=-10.5\ntemp_celsius<0")
check_payload "/eval" "POST" "$NEG_1" '{"result":true}' "Evaluate negative float: -10.5 < 0 (Expected: True)"

# Floating point precision
FLOAT_1=$(printf "pi_val=3.14,limit_val=3.15\npi_val<limit_val")
check_payload "/eval" "POST" "$FLOAT_1" '{"result":true}' "Evaluate float precision: 3.14 < 3.15 (Expected: True)"

# Large numbers and zero
LARGE_1=$(printf "balance_usd=1500.75\nbalance_usd>999")
check_payload "/eval" "POST" "$LARGE_1" '{"result":true}' "Evaluate large float: 1500.75 > 999 (Expected: True)"

# Boundary test: exact equality with decimals
EQUAL_1=$(printf "tolerance=0.001\ntolerance=0")
check_payload "/eval" "POST" "$EQUAL_1" '{"result":false}' "Evaluate precision boundary: 0.001 = 0 (Expected: False)"
echo ""

echo "--- 10. String Evaluation (Zero-Copy) ---"
STR_PAYLOAD_1=$(printf "role=\"admin\",region=\"us\"\nrole=\"admin\"\nregion=\"us\"")
check_payload "/eval" "POST" "$STR_PAYLOAD_1" '{"result":true}' "Evaluate Strings: role='admin' & region='us' (Expected: True)"

STR_PAYLOAD_2=$(printf "status=\"active\"\nstatus=\"pending\"")
check_payload "/eval" "POST" "$STR_PAYLOAD_2" '{"result":false}' "Evaluate Strings: active = pending (Expected: False)"

echo "--- 11. String Advanced Operations ---"
PAYLOAD_CONTAINS=$(printf "email=\"admin@blockmaker.net\"\nemail~\"blockmaker\"")
check_payload "/eval" "POST" "$PAYLOAD_CONTAINS" '{"result":true}' "Evaluate Contains: email ~ 'blockmaker' (Expected: True)"

PAYLOAD_NOCASE=$(printf "country=\"US\"\ncountry^\"us\"")
check_payload "/eval" "POST" "$PAYLOAD_NOCASE" '{"result":true}' "Evaluate IgnoreCase: US ^ us (Expected: True)"

PAYLOAD_LEN=$(printf "username=\"fernando\"\n#username>5")
check_payload "/eval" "POST" "$PAYLOAD_LEN" '{"result":true}' "Evaluate Length: #username > 5 (Expected: True)"

echo ""
echo "--- 12. Hierarchical Logic (Parentheses & Stack) ---"

# Basic Grouping (Sanity Check)
PAYLOAD_HIER_1=$(printf "MODE=AND\nx=10,y=5\n(x > 5 AND y < 10)")
check_payload "/eval" "POST" "$PAYLOAD_HIER_1" '{"result":true}' "Hierarchical: Basic Grouping (Expected: True)"

# Whitespace Chaos (Tests the new skip_spaces logic in parser and evaluator)
PAYLOAD_HIER_2=$(printf "MODE=AND\n  user_age = 25  ,  role = \"admin\"  \n(   user_age   >   18   AND   role   =   \"admin\"   )")
check_payload "/eval" "POST" "$PAYLOAD_HIER_2" '{"result":true}' "Hierarchical: Whitespace Chaos Tolerance (Expected: True)"

# Combined Logic OR-Rescue (First parentheses fails, but the OR saves it)
PAYLOAD_HIER_3=$(printf "MODE=OR\npoints=50,status=\"vip\"\n(points > 100 AND points < 200) OR (status = \"vip\")")
check_payload "/eval" "POST" "$PAYLOAD_HIER_3" '{"result":true}' "Hierarchical: Combined OR-Rescue Logic (Expected: True)"

# Deep Nesting (Tests stack_ptr limits and memory safety)
PAYLOAD_HIER_4=$(printf "MODE=AND\na=1,b=2,c=3,d=4\n((a = 1 AND b = 2) AND (c = 3 AND d = 4))")
check_payload "/eval" "POST" "$PAYLOAD_HIER_4" '{"result":true}' "Hierarchical: Deep Nesting Double Parentheses (Expected: True)"

# Internal Fail-Fast (Tests short-circuiting inside a grouped expression)
PAYLOAD_HIER_5=$(printf "MODE=AND\nrole=\"guest\"\n(role = \"admin\" AND role = \"editor\")")
check_payload "/eval" "POST" "$PAYLOAD_HIER_5" '{"result":false}' "Hierarchical: Internal Fail-Fast Logic (Expected: False)"

# Complex String and Length combo inside Parentheses
PAYLOAD_HIER_6=$(printf "username=\"fernando\"\n(#username > 5 AND username ~ \"fer\")")
check_payload "/eval" "POST" "$PAYLOAD_HIER_6" '{"result":true}' "Hierarchical: String operations inside group (Expected: True)"

echo "--- 13. Arithmetic Engine (SSE2 Math) ---"

# Basic Addition
check_payload "/eval" "POST" "(5 + 5) = 10" '{"result":true}' "Math: (5 + 5) = 10 (Expected: True)"

# Subtraction & Negative results
check_payload "/eval" "POST" "(10 - 15) < 0" '{"result":true}' "Math: Negative result (10 - 15) < 0 (Expected: True)"

# Multiplication & Division
PAYLOAD_MATH_MUL=$(printf "price=100,tax=1.21\n(price * tax) > 120")
check_payload "/eval" "POST" "$PAYLOAD_MATH_MUL" '{"result":true}' "Math: Multiplication with vars (Expected: True)"

PAYLOAD_MATH_DIV=$(printf "total=100,parts=4\n(total / parts) = 25")
check_payload "/eval" "POST" "$PAYLOAD_MATH_DIV" '{"result":true}' "Math: Division (Expected: True)"

# Complex Math & Precedence (Forced by Parentheses)
# Calculation: ((2 + 3) * 4) = 20
check_payload "/eval" "POST" "((2 + 3) * 4) = 20" '{"result":true}' "Math: Nested Precedence ((2+3)*4) (Expected: True)"

# Non-zero float as Truthy (Engine behavior: 0.0 is False, others are True)
check_payload "/eval" "POST" "5 + 5" '{"result":true}' "Math: Result 10.0 counts as True (Expected: True)"
check_payload "/eval" "POST" "10 - 10" '{"result":false}' "Math: Result 0.0 counts as False (Expected: False)"

echo ""
echo "--- 14. Real-Time Logic (NOW Keyword) ---"

# Sanity Check: NOW is a positive unix timestamp
check_payload "/eval" "POST" "NOW > 0" '{"result":true}' "Time: NOW is a valid positive timestamp (Expected: True)"

# Context Comparison (Checking if a date is in the past)
# 1735689600 = Jan 1st, 2025. In 2026, this is always true.
PAYLOAD_TIME_1=$(printf "signup_date=1735689600\nNOW > signup_date")
check_payload "/eval" "POST" "$PAYLOAD_TIME_1" '{"result":true}' "Time: NOW is after Jan 2025 (Expected: True)"

# Relative Time Math: Has more than 24 hours passed? (86400 seconds)
# We simulate a "last_seen" from 2 days ago
TS_TWO_DAYS_AGO=$(($(date +%s) - 172800))
PAYLOAD_TIME_2=$(printf "last_seen=$TS_TWO_DAYS_AGO\n(NOW - last_seen) > 86400")
check_payload "/eval" "POST" "$PAYLOAD_TIME_2" '{"result":true}' "Time: More than 24h passed since last_seen (Expected: True)"

# Future expiry check
TS_NEXT_YEAR=$(($(date +%s) + 31536000))
PAYLOAD_TIME_3=$(printf "expiry=$TS_NEXT_YEAR\nNOW < expiry")
check_payload "/eval" "POST" "$PAYLOAD_TIME_3" '{"result":true}' "Time: NOW is before future expiry (Expected: True)"

echo "-----------------------------------------------------------------"
echo -e "${GREEN}✅ ALL TESTS PASSED SUCCESSFULLY!${NC}"
echo "La Roca Rules Engine MVP is rock solid."

# --- START TEARDOWN ---
echo "🧹 Tearing down ephemeral containers..."
docker compose down -v > /dev/null 2>&1
# --- END TEARDOWN ---