#!/bin/bash
# generate_chart.sh (Sed 치환 방식 도입 최종 수정본)

# 현재 디렉토리가 워크플로우 실행 디렉토리인지 확인
if [ ! -d ".git" ]; then
    echo "ERROR: 이 스크립트는 Git 저장소 디렉토리 내에서 실행되어야 합니다." >&2
    exit 1
fi

# API 키 확인
if [ -z "$GEMINI_API_KEY" ]; then
    echo "ERROR: GEMINI_API_KEY 환경 변수가 설정되지 않았습니다." >&2
    exit 1
fi

# ====================================================================
# 1. 데이터 파싱 및 가공
# ====================================================================

if [ ! -f "result.txt" ]; then
    echo "ERROR: result.txt 파일을 찾을 수 없습니다. check.sh를 먼저 실행해야 합니다." >&2
    exit 1
fi

sed -i '/^$/d' result.txt

# 전체 데이터를 최신 30개 항목만 사용
tail -n 30 result.txt > /tmp/recent_data.txt
DATA_LINES="/tmp/recent_data.txt"

# 최종 업데이트 시간 추출
LAST_UPDATE_TIME=$(tail -n 1 result.txt | awk -F ' : ' '{print $1}' | sed 's/\//\\\//g') # sed 치환을 위해 / 이스케이프

LABELS=()
VALUES=()
declare -A DAILY_DATA

# 1.1. 차트 데이터 (시간별) 생성
while IFS=' : ' read -r datetime value; do
    clean_value=$(echo "$value" | sed 's/,//g')
    LABELS+=("$(echo "$datetime")")
    VALUES+=("$clean_value")
done < "$DATA_LINES"

# 1.2. 일별 데이터 추출
while IFS=' : ' read -r datetime value; do
    date_part=$(echo "$datetime" | awk '{print $1}')
    clean_value=$(echo "$value" | sed 's/,//g')
    DAILY_DATA["$date_part"]="$clean_value"
done < result.txt

# 1.3. Chart.js 데이터셋 JSON 생성
chart_labels=$(printf '"%s", ' "${LABELS[@]}" | sed 's/, $//')
chart_values=$(IFS=','; echo "${VALUES[*]}")
RAW_DATA_STRING=$(cat "$DATA_LINES" | sed -E ':a;N;$!ba;s/\n/\\n/g')


chart_data_raw=$(cat <<EOD
{
    "raw_data_string": "${RAW_DATA_STRING}",
    "labels": [${chart_labels}],
    "values": [${chart_values}]
}
EOD
)
# sed 치환을 위해: 한 줄로 만들고 내부 /를 이스케이프 처리
chart_data=$(echo "$chart_data_raw" | tr -d '\n' | sed 's/\//\\\//g') 

# ====================================================================
# 2. HTML 테이블 생성 함수 (sed 치환을 위한 특수 문자 이스케이프 추가)
# ====================================================================

# HTML 테이블 생성 및 sed 치환을 위한 이스케이프 처리 함수
escape_for_sed() {
    # 1. 개행 문자를 제거
    # 2. sed의 구분자로 사용될 / 문자를 이스케이프 (\/)
    # 3. sed 치환 오류를 유발하는 & 문자를 이스케이프 (\&)
    echo "$1" | tr -d '\n' | sed 's/\//\\\//g' | sed 's/\&/\\&/g'
}

# 2.1. 일별 테이블 HTML 생성 함수
generate_daily_table() {
    local data_lines=()
    for date in "${!DAILY_DATA[@]}"; do
        data_lines+=("$date : ${DAILY_DATA[$date]}")
    done
    
    sorted_daily_data=$(printf "%s\n" "${data_lines[@]}" | sort -r)

    local table_rows=""
    local previous_value_int=0 
    local temp_rows=""

    while IFS=' : ' read -r date value_str; do
        if [ -z "$date" ]; then continue; fi
        current_value_int=$(echo "$value_str" | sed 's/,//g')
        if ! [[ "$current_value_int" =~ ^[0-9]+$ ]]; then continue; fi
        formatted_value=$(echo "$current_value_int" | sed ':a;s/\B[0-9]\{3\}\>/,&/;ta')
        
        local change_str="---"
        local class_name="zero" 
        
        if [ "$previous_value_int" -ne 0 ]; then
            change=$((current_value_int - previous_value_int))
            change_abs=$(echo "$change" | sed 's/-//')
            formatted_change=$(echo "$change_abs" | sed ':a;s/\B[0-9]\{3\}\>/,&/;ta')

            if [ "$change" -gt 0 ]; then
                class_name="plus" 
                change_str="+$formatted_change"
            elif [ "$change" -lt 0 ]; then
                class_name="minus" 
                change_str="-$formatted_change"
            else
                class_name="zero"
                change_str="0"
            fi
        fi

        temp_rows=$(cat <<EOT
$temp_rows
<tr>
    <td class="first-col">$date</td>
    <td class="value-col">$formatted_value</td>
    <td class="$class_name">$change_str</td>
</tr>
EOT
)
        previous_value_int=$current_value_int 
    done <<< "$sorted_daily_data"

    table_rows=$(echo "$temp_rows" | tac)


    daily_table_html=$(cat <<EOD
<table class="data-table">
<thead>
    <tr>
        <th class="header-col">날짜</th>
        <th class="header-col right-align">값</th>
        <th class="header-col right-align">변화</th>
    </tr>
</thead>
<tbody>
$table_rows
</tbody>
</table>
EOD
)
    # sed 치환을 위해 이스케이프 처리
    echo "$(escape_for_sed "$daily_table_html")"
}

# 2.2. 시간별 테이블 HTML 생성 함수
generate_hourly_table() {
    local table_rows=""
    local previous_value_int=0 
    local reverse_data=$(cat "$DATA_LINES") 

    local temp_rows=""
    while IFS=' : ' read -r datetime value_str; do
        if [ -z "$datetime" ]; then continue; fi
        current_value_int=$(echo "$value_str" | sed 's/,//g')
        if ! [[ "$current_value_int" =~ ^[0-9]+$ ]]; then continue; fi
        formatted_value=$(echo "$current_value_int" | sed ':a;s/\B[0-9]\{3\}\>/,&/;ta')
        
        local change_str="---"
        local class_name="zero" 
        
        if [ "$previous_value_int" -ne 0 ]; then
            change=$((current_value_int - previous_value_int))
            change_abs=$(echo "$change" | sed 's/-//')
            formatted_change=$(echo "$change_abs" | sed ':a;s/\B[0-9]\{3\}\>/,&/;ta')

            if [ "$change" -gt 0 ]; then
                class_name="plus" 
                change_str="+$formatted_change"
            elif [ "$change" -lt 0 ]; then
                class_name="minus" 
                change_str="-$formatted_change"
            else
                class_name="zero"
                change_str="0"
            fi
        fi

        temp_rows=$(cat <<EOT
$temp_rows
<tr>
    <td class="first-col">$datetime</td>
    <td class="value-col">$formatted_value</td>
    <td class="$class_name">$change_str</td>
</tr>
EOT
)
        previous_value_int=$current_value_int 
    done <<< "$reverse_data"

    table_rows=$(echo "$temp_rows" | tac)


    hourly_table_html=$(cat <<EOD
<table class="data-table">
<thead>
    <tr>
        <th class="header-col">시간</th>
        <th class="header-col right-align">값</th>
        <th class="header-col right-align">변화</th>
    </tr>
</thead>
<tbody>
$table_rows
</tbody>
</table>
EOD
)
    # sed 치환을 위해 이스케이프 처리
    echo "$(escape_for_sed "$hourly_table_html")"
}

# 테이블 생성 실행
daily_table=$(generate_daily_table)
hourly_table=$(generate_hourly_table)

# ====================================================================
# 3. AI 예측 및 분석 (Gemini API 사용)
# ====================================================================

# 3.1. 분석을 위한 데이터 준비
analysis_data=$(cat "$DATA_LINES")
CURRENT_DATE=$(date +"%Y-%m-%d")

echo "3.2. Gemini API 호출 시작..."
API_ENDPOINT="https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=${GEMINI_API_KEY}"

# MMORPG 게임 매출 분석 프롬프트 (달러($) 반영, 조언 제외)
prompt_text=$(cat <<EOP
당신은 출시 5일차(10월 28일 오픈) MMORPG 모바일/PC 게임의 매출 분석가입니다. 아래 데이터는 매분 수집된 매출 추정치 시계열 데이터입니다.

**게임 정보:**
* 장르: MMORPG (모바일/PC)
* 오픈일: 2025년 10월 28일
* 서비스 지역: 전 세계 180개국
* 데이터 값: 매출 추정치 (달러 $ 값, 환율/세금 미포함 RAW 데이터)

**[데이터]**
$analysis_data

**[분석 지침]**
분석은 간결하고 명료하게, 순수 예측 및 분석 결과만 제공해야 합니다.
1.  **초기 성장 분석 (5일차 누적):** 출시 초기 5일간의 전반적인 매출 추이(상승, 하락, 정체)와 추세가 MMORPG 특성상 건강한지 평가하세요.
2.  **금일 예상 매출 예측:** 현재 시간까지의 데이터($CURRENT_DATE)를 바탕으로, 오늘 하루(23:59:59까지)의 총 예상 매출 규모를 구체적인 **달러($)** 숫자로 제시하세요.
3.  **이달 (11월) 총 예상 매출 예측:** 현재 추세가 유지된다고 가정하고, 11월 총 예상 매출을 합리적인 **달러($)** 숫자로 예측하세요.
4.  **출력 형식:** 분석 결과만 (마크다운 없이) 두 문단 이내로 작성해 주세요. (예측치는 **달러($) 기호**와 쉼표가 포함된 형태로 제시)
EOP
)

# JSON 본문 생성
json_content=$(echo "$prompt_text" | jq -s -R '.' | tr -d '\n')
json_payload=$(cat <<EOD
{
    "contents": [
        {
            "parts": [
                {
                    "text": $json_content
                }
            ]
        }
    ]
}
EOD
)

# cURL을 사용하여 API 호출
response=$(curl -s -X POST -H "Content-Type: application/json" -d "$json_payload" "$API_ENDPOINT")

# 3.3. 응답 파싱
if [ -z "$response" ]; then
    ai_prediction="Gemini API 응답을 받지 못했습니다. 네트워크 또는 API 문제일 수 있습니다."
else
    ai_prediction_raw=$(echo "$response" | jq -r '.candidates[0].content.parts[0].text' 2>/dev/null)
    
    if [ -z "$ai_prediction_raw" ] || [ "$ai_prediction_raw" == "null" ]; then
        error_message=$(echo "$response" | html2text)
        ai_prediction="AI 예측 실패. 응답 오류: ${error_message}"
    else
        # 개행 문자를 <br>로 치환
        ai_prediction=$(echo "$ai_prediction_raw" | sed ':a;N;$!ba;s/\n/<br>/g')
    fi
fi

# sed 치환을 위해 이스케이프 처리
ai_prediction=$(escape_for_sed "$ai_prediction")

echo "3.4. AI 예측 완료."

# ====================================================================
# 4. 최종 index.html 파일 생성 및 변수 삽입 (Sed 스크립트 파일 사용)
# ====================================================================

# 템플릿 다운로드
WGET_TEMPLATE_URL="https://raw.githubusercontent.com/alexcha/test1/refs/heads/main/template.html"
wget "$WGET_TEMPLATE_URL" -O template.html || { echo "ERROR: template.html 다운로드 실패" >&2; exit 1; }

echo "4.1. index.html 파일 생성 시작 (Sed 스크립트 방식)..."

# 템플릿 파일 복사
cp template.html index.html

# Sed를 사용하여 변수 치환 실행 (변수가 비어있더라도 치환 토큰 자체는 제거됨)
# 4개의 치환을 한 번에 실행

sed -i "s/__CHART_DATA__/$chart_data/g" index.html
sed -i "s/__AI_PREDICTION__/$ai_prediction/g" index.html
sed -i "s/__DAILY_TABLE_HTML__/$daily_table/g" index.html
sed -i "s/__HOURLY_TABLE_HTML__/$hourly_table/g" index.html
sed -i "s/__LAST_UPDATE_TIME__/$LAST_UPDATE_TIME/g" index.html

echo "4.2. index.html 파일 생성 완료. 파일 크기: $(wc -c < index.html) 바이트"
