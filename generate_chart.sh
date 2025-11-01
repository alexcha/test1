#!/bin/bash
# generate_chart.sh

# 현재 디렉토리가 워크플로우 실행 디렉토리인지 확인 (불필요한 경로 오류 방지)
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

# result.txt 파일이 없으면 오류
if [ ! -f "result.txt" ]; then
    echo "ERROR: result.txt 파일을 찾을 수 없습니다. check.sh를 먼저 실행해야 합니다." >&2
    exit 1
fi

# result.txt에서 공백 줄 제거 (파싱 오류 방지)
sed -i '/^$/d' result.txt

# 전체 데이터를 최신 30개 항목만 사용 (차트 부하 줄이기 및 최신 데이터 집중)
tail -n 30 result.txt > /tmp/recent_data.txt
DATA_LINES="/tmp/recent_data.txt"

# 배열 초기화
LABELS=()
VALUES=()
DAILY_DATA=() # 일별 요약 데이터 (날짜와 최종 값)

# 1.1. 차트 데이터 (시간별) 생성
while IFS=' : ' read -r datetime value; do
    # 시간과 값만 추출
    time_part=$(echo "$datetime" | awk '{print $2}')
    clean_value=$(echo "$value" | sed 's/,//g')

    LABELS+=("$(echo "$datetime" | awk '{print $1" "$2}')") # 날짜와 시간
    VALUES+=("$clean_value")
done < "$DATA_LINES"

# 1.2. 일별 데이터 추출 (날짜별 마지막 값만)
while IFS=' : ' read -r datetime value; do
    date_part=$(echo "$datetime" | awk '{print $1}')
    clean_value=$(echo "$value" | sed 's/,//g')

    # key=날짜, value=값으로 저장. 나중에 입력된 값이 최종값
    DAILY_DATA["$date_part"]="$clean_value"
done < result.txt

# 1.3. Chart.js 데이터셋 JSON 생성
chart_labels=$(IFS=','; echo "${LABELS[*]}")
chart_values=$(IFS=','; echo "${VALUES[*]}")

chart_data=$(cat <<EOD
{
    "labels": ["${chart_labels//,/\", \"}"],
    "datasets": [{
        "label": "값 추이",
        "data": [${chart_values}],
        "borderColor": "rgba(0, 123, 255, 1)",
        "backgroundColor": "rgba(0, 123, 255, 0.1)",
        "tension": 0.3,
        "fill": true
    }]
}
EOD
)

# ====================================================================
# 2. HTML 테이블 생성 함수
# ====================================================================

# 2.1. 일별 테이블 HTML 생성 함수
generate_daily_table() {
    local data_lines=()
    for date in "${!DAILY_DATA[@]}"; do
        data_lines+=("$date : ${DAILY_DATA[$date]}")
    done
    
    # 내림차순 정렬 (최신 날짜가 위로)
    sorted_daily_data=$(printf "%s\n" "${data_lines[@]}" | sort -r)

    local table_rows=""
    local previous_value=0

    while IFS=' : ' read -r date value_str; do
        if [ -z "$date" ]; then continue; fi

        current_value=$(echo "$value_str" | sed 's/,//g')
        formatted_value=$(echo "$current_value" | sed ':a;s/\B[0-9]\{3\}\>/,&/;ta')
        
        local change_val=""
        local change_str="---"
        local color="#6c757d" # 회색 (기본값)
        
        if [ "$previous_value" -ne 0 ]; then
            change=$((current_value - previous_value))
            change_abs=$(echo "$change" | sed 's/-//')
            formatted_change=$(echo "$change_abs" | sed ':a;s/\B[0-9]\{3\}\>/,&/;ta')

            if [ "$change" -gt 0 ]; then
                change_str="+$formatted_change"
                color="#dc3545" # 빨간색
            elif [ "$change" -lt 0 ]; then
                change_str="-$formatted_change"
                color="#007bff" # 파란색
            else
                change_str="0"
                color="#333"
            fi
        fi

        # 테이블 행 생성 (최신 데이터가 위로 오도록)
        table_rows=$(cat <<EOT
<tr>
    <td style="padding: 12px; border-top: 1px solid #eee; border-right: 1px solid #eee; text-align: left; background-color: white; color: #343a40;">$date</td>
    <td style="padding: 12px; border-top: 1px solid #eee; border-right: 1px solid #eee; text-align: right; background-color: white; font-weight: bold; color: #333;">$formatted_value</td>
    <td style="padding: 12px; border-top: 1px solid #eee; text-align: right; background-color: white; color: $color; font-weight: 600;">$change_str</td>
</tr>
$table_rows
EOT
)
        previous_value=$current_value
    done <<< "$sorted_daily_data"

    # 테이블 헤더 추가
    daily_table=$(cat <<EOD
<table style="width: 100%; max-width: 1000px; border-collapse: separate; border-spacing: 0; border: 1px solid #ddd; font-size: 14px; min-width: 300px; border-radius: 8px; overflow: hidden; margin-top: 20px;">
<thead>
    <tr>
        <th style="padding: 14px; background-color: #f1f1f1; border-right: 1px solid #ccc; text-align: left; color: #333;">날짜</th>
        <th style="padding: 14px; background-color: #f1f1f1; border-right: 1px solid #ccc; text-align: right; color: #333;">값</th>
        <th style="padding: 14px; background-color: #f1f1f1; text-align: right; color: #333;">변화</th>
    </tr>
</thead>
<tbody>
$table_rows
</tbody>
</table>
EOD
)

    echo "$daily_table"
}

# 2.2. 시간별 테이블 HTML 생성 함수
generate_hourly_table() {
    local table_rows=""
    local previous_value=0
    local reverse_data=$(cat "$DATA_LINES" | tac) # 최신 데이터가 위로 오도록 역순 처리

    while IFS=' : ' read -r datetime value_str; do
        if [ -z "$datetime" ]; then continue; fi

        current_value=$(echo "$value_str" | sed 's/,//g')
        formatted_value=$(echo "$current_value" | sed ':a;s/\B[0-9]\{3\}\>/,&/;ta')
        
        local change_val=""
        local change_str="---"
        local color="#6c757d" # 회색 (기본값)
        
        if [ "$previous_value" -ne 0 ]; then
            change=$((current_value - previous_value))
            change_abs=$(echo "$change" | sed 's/-//')
            formatted_change=$(echo "$change_abs" | sed ':a;s/\B[0-9]\{3\}\>/,&/;ta')

            if [ "$change" -gt 0 ]; then
                change_str="+$formatted_change"
                color="#dc3545" # 빨간색
            elif [ "$change" -lt 0 ]; then
                change_str="-$formatted_change"
                color="#007bff" # 파란색
            else
                change_str="0"
                color="#333"
            fi
        fi

        # 테이블 행 생성
        table_rows=$(cat <<EOT
<tr>
    <td style="padding: 12px; border-top: 1px solid #eee; border-right: 1px solid #eee; text-align: left; background-color: white;">$datetime</td>
    <td style="padding: 12px; border-top: 1px solid #eee; border-right: 1px solid #eee; text-align: right; font-weight: bold; color: #333; background-color: white;">$formatted_value</td>
    <td style="padding: 12px; border-top: 1px solid #eee; text-align: right; background-color: white; color: $color; font-weight: 600;">$change_str</td>
</tr>
$table_rows
EOT
)
        previous_value=$current_value
    done <<< "$reverse_data"

    # 테이블 헤더 추가
    hourly_table=$(cat <<EOD
<table style="width: 100%; max-width: 1000px; border-collapse: separate; border-spacing: 0; border: 1px solid #ddd; font-size: 14px; min-width: 300px; border-radius: 8px; overflow: hidden;">
<thead>
    <tr>
        <th style="padding: 14px; background-color: #f1f1f1; border-right: 1px solid #ccc; text-align: left; color: #333;">시간</th>
        <th style="padding: 14px; background-color: #f1f1f1; border-right: 1px solid #ccc; text-align: right; color: #333;">값</th>
        <th style="padding: 14px; background-color: #f1f1f1; text-align: right; color: #333;">변화</th>
    </tr>
</thead>
<tbody>
$table_rows
</tbody>
</table>
EOD
)

    echo "$hourly_table"
}

# 테이블 생성 실행
daily_table=$(generate_daily_table)
hourly_table=$(generate_hourly_table)

# ====================================================================
# 3. AI 예측 및 분석 (Gemini API 사용)
# ====================================================================

# 3.1. 분석을 위한 데이터 준비
# 전체 데이터 텍스트 (최대 30개 항목)를 Gemini 모델에 전달
analysis_data=$(cat "$DATA_LINES")

# 3.2. Gemini API 호출
echo "3.2. Gemini API 호출 시작..."
API_ENDPOINT="https://generativelanguage.googleapis.com/v1/models/gemini-2.5-flash:generateContent?key=${GEMINI_API_KEY}"

# 프롬프트 정의
prompt_text=$(cat <<EOP
당신은 금융 데이터 분석가입니다. 아래 데이터는 시간: 값 형식의 시계열 데이터입니다.
[데이터]
$analysis_data

[분석 지침]
1.  **최근 추세 분석**: 데이터의 최근 3일간의 변화를 분석하세요 (상승/하락 추세).
2.  **예측**: 다음 측정 시점(약 1~2시간 후)의 값을 합리적으로 예측하세요.
3.  **요약**: 이 상황을 한 줄로 요약하세요.
4.  **출력 형식**: 분석 결과만 (마크다운 없이) 한 문단으로 작성해 주세요.
EOP
)

# JSON 본문 생성
json_payload=$(cat <<EOD
{
    "contents": [
        {
            "parts": [
                {
                    "text": "$prompt_text"
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
    # jq를 사용하여 'text' 필드 추출
    ai_prediction=$(echo "$response" | jq -r '.candidates[0].content.parts[0].text' 2>/dev/null)
    
    if [ -z "$ai_prediction" ] || [ "$ai_prediction" == "null" ]; then
        # 오류 메시지 또는 API 응답 전문 저장
        error_message=$(echo "$response" | html2text)
        ai_prediction="AI 예측 실패. 응답 오류: $error_message"
    fi
fi

echo "3.4. AI 예측 완료."

# ====================================================================
# 4. 최종 index.html 파일 생성 및 변수 삽입
# ====================================================================

# 템플릿 다운로드
WGET_TEMPLATE_URL="https://raw.githubusercontent.com/alexcha/test1/refs/heads/main/template.html"
wget "$WGET_TEMPLATE_URL" -O template.html || { echo "ERROR: template.html 다운로드 실패" >&2; exit 1; }

echo "4.1. index.html 파일 생성 시작 (토큰 치환)..."

# index.html 파일 생성 및 변수 삽입
# 긴 문자열 대신 짧은 토큰을 사용하여 sed 오류 방지
cat template.html | \
sed "s|__CHART_DATA__|${chart_data}|g" | \
sed "s|__AI_PREDICTION__|${ai_prediction}|g" | \
sed "s|__DAILY_TABLE_HTML__|${daily_table}|g" | \
sed "s|__HOURLY_TABLE_HTML__|${hourly_table}|g" > index.html

echo "4.2. index.html 파일 생성 완료. 파일 크기: $(wc -c < index.html) 바이트"
