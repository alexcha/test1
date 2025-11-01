#!/bin/bash
# generate_chart.sh (데이터 파싱 및 구문 안정화 버전)

# ----------------------------------------------------------------------
# 이 스크립트는 AWK를 사용하여 멀티라인 데이터를 JavaScript 템플릿 리터럴(` `)에 
# 안전하게 삽입하도록 수정되었습니다. (복잡한 JSON 생성 로직 제거)
# ----------------------------------------------------------------------

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

# 빈 줄 제거
sed -i '/^$/d' result.txt

# **중요:** HTML의 JS로 전달할 전체 원시 데이터 문자열 (줄바꿈 포함)
# 이 데이터를 AWK로 치환하여 JS 백틱 안에 넣을 것입니다.
RAW_DATA_FOR_JS=$(cat result.txt)

# 최종 업데이트 시간 추출 (sed 치환을 위해 ~ 이스케이프)
LAST_UPDATE_TIME=$(tail -n 1 result.txt | awk -F ' : ' '{print $1}' | sed 's/\~/\\~/g') 

# 일별 데이터 추출을 위해 result.txt 전체 사용
declare -A DAILY_DATA

# 1.1. 일별 데이터 추출
# CRITICAL FIX: IFS를 ":"로 설정하고 xargs로 앞뒤 공백 제거하여 정확하게 "시각"과 "값"만 분리
while IFS=":" read -r datetime_raw value_raw; do
    # 앞뒤 공백 제거
    datetime=$(echo "$datetime_raw" | xargs)
    value=$(echo "$value_raw" | xargs)

    date_part=$(echo "$datetime" | awk '{print $1}')
    clean_value=$(echo "$value" | sed 's/,//g')

    # 데이터가 유효한지 확인하고 DAILY_DATA에 저장 (가장 마지막 값이 일별 최종값)
    if [[ -n "$clean_value" && "$clean_value" =~ ^[0-9]+$ ]]; then
        DAILY_DATA["$date_part"]="$clean_value"
    fi
done < result.txt

# **기존의 LABELS 및 VALUES 배열 생성 로직과 JSON 생성 로직은 제거되었습니다.**
# 이제 JavaScript가 RAW_DATA_CONTENT를 파싱하여 차트를 그립니다.

# ====================================================================
# 2. HTML 테이블 생성 함수 (sed 치환 안정화)
# ====================================================================

# HTML 테이블 생성 및 sed 치환을 위한 이스케이프 처리 함수
escape_for_sed() {
    # sed의 구분자로 사용될 ~ 문자를 이스케이프 (\~)
    # sed 치환 오류를 유발하는 & 문자를 이스케이프 (\&)
    # 줄바꿈 제거 (AI 예측 텍스트는 별도로 <br> 치환이 필요)
    echo "$1" | tr -d '\n' | sed 's/\~/\\~/g' | sed 's/\&/\\&/g'
}

# 2.1. 일별 테이블 HTML 생성 함수
generate_daily_table() {
    local data_lines=()
    for date in "${!DAILY_DATA[@]}"; do
        # '날짜 : 값' 형식으로 data_lines 배열에 추가
        data_lines+=("$date : ${DAILY_DATA[$date]}")
    done
    
    if [ ${#data_lines[@]} -eq 0 ]; then
        echo "$(escape_for_sed "<tr><td colspan='3' style='text-align: center; color: #6c757d;'>데이터를 찾을 수 없습니다.</td></tr>")"
        return
    fi
    
    # 날짜를 기준으로 내림차순 정렬 (최신 날짜가 위에)
    sorted_daily_data=$(printf "%s\n" "${data_lines[@]}" | sort -k1,1 -r)

    local table_rows=""
    local previous_value_int=0 
    local temp_rows=""
    
    # 정렬된 데이터를 다시 읽어서 변화량 계산
    while IFS=' : ' read -r date value_str; do
        if [ -z "$date" ]; then continue; fi
        current_value_int=$(echo "$value_str" | sed 's/,//g')
        if ! [[ "$current_value_int" =~ ^[0-9]+$ ]]; then 
            previous_value_int=0 
            continue 
        fi
        
        # 숫자를 천 단위로 포맷팅
        formatted_value=$(echo "$current_value_int" | sed ':a;s/\B[0-9]\{3\}\>/,&/;ta')
        
        local change_str="---"
        local class_name="zero" 
        
        # 이전 날짜의 값이 있으면 변화량 계산 (역순으로 계산되지만, 이전 날짜와 비교하는 것은 맞음)
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
    <td class="value-col right-align">$formatted_value</td>
    <td class="$class_name right-align">$change_str</td>
</tr>
EOT
)
        previous_value_int=$current_value_int 
    done <<< "$sorted_daily_data"

    # 최종적으로 생성된 테이블 행을 역순으로 뒤집어 오름차순(오래된 데이터가 위로)으로 표시
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
    # sed 치환을 위해 이스케이프 처리 (줄바꿈이 사라짐)
    echo "$(escape_for_sed "$daily_table_html")"
}

# 2.2. 시간별 테이블 HTML 생성 함수
generate_hourly_table() {
    local table_rows=""
    local previous_value_int=0 
    # 차트와 동일하게 최근 30개 항목만 사용
    local reverse_data=$(tail -n 30 result.txt) 

    if [ -z "$reverse_data" ]; then
        echo "$(escape_for_sed "<tr><td colspan='3' style='text-align: center; color: #6c757d;'>데이터를 찾을 수 없습니다.</td></tr>")"
        return
    fi

    local temp_rows=""
    # 데이터는 이미 시간순으로 되어 있음
    while IFS=":" read -r datetime_raw value_raw; do
        # 앞뒤 공백 제거
        datetime=$(echo "$datetime_raw" | xargs)
        value_str=$(echo "$value_raw" | xargs)
        
        if [ -z "$datetime" ]; then continue; fi
        current_value_int=$(echo "$value_str" | sed 's/,//g')
        if ! [[ "$current_value_int" =~ ^[0-9]+$ ]]; then 
            previous_value_int=0 
            continue 
        fi
        
        formatted_value=$(echo "$current_value_int" | sed ':a;s/\B[0-9]\{3\}\>/,&/;ta')
        
        local change_str="---"
        local class_name="zero" 
        
        if [ "$previous_value_int" -ne 0 ]; then
            # 현재 데이터 - 이전 데이터 (정방향 변화량)
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
    <td class="value-col right-align">$formatted_value</td>
    <td class="$class_name right-align">$change_str</td>
</tr>
EOT
)
        previous_value_int=$current_value_int 
    done <<< "$reverse_data"

    # 테이블 행을 역순으로 뒤집어 최신 데이터가 위에 오도록 설정
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
    # sed 치환을 위해 이스케이프 처리 (줄바꿈이 사라짐)
    echo "$(escape_for_sed "$hourly_table_html")"
}

# 테이블 생성 실행
daily_table=$(generate_daily_table)
hourly_table=$(generate_hourly_table)

# ====================================================================
# 3. AI 예측 및 분석 (Gemini API 사용)
# ====================================================================

API_ENDPOINT="https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=${GEMINI_API_KEY}"
analysis_data=$(tail -n 30 result.txt)
CURRENT_DATE=$(date +"%Y-%m-%d")

echo "3.2. Gemini API 호출 시작..."

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

response=$(curl -s -X POST -H "Content-Type: application/json" -d "$json_payload" "$API_ENDPOINT")

if [ -z "$response" ]; then
    # AI 예측 결과에서 줄바꿈을 <br>로 치환
    ai_prediction=$(echo "Gemini API 응답을 받지 못했습니다. 네트워크 또는 API 문제일 수 있습니다." | sed 's/\n/<br>/g')
else
    ai_prediction_raw=$(echo "$response" | jq -r '.candidates[0].content.parts[0].text' 2>/dev/null)
    
    if [ -z "$ai_prediction_raw" ] || [ "$ai_prediction_raw" == "null" ]; then
        error_message=$(echo "$response" | html2text)
        ai_prediction=$(echo "AI 예측 실패. 응답 오류: ${error_message}" | sed 's/\n/<br>/g')
    else
        # AI 예측 결과에서 줄바꿈을 <br>로 치환하여 HTML에 삽입
        ai_prediction=$(echo "$ai_prediction_raw" | sed ':a;N;$!ba;s/\n/<br>/g')
    fi
fi

ai_prediction=$(escape_for_sed "$ai_prediction")

echo "3.4. AI 예측 완료."

# ====================================================================
# 4. 최종 index.html 파일 생성 및 변수 삽입 (Sed + AWK 스크립트 파일 사용)
# ====================================================================

echo "4.1. index.html 파일 생성 시작 (Sed + AWK 사용)..."

cp template.html index.html

# 4.1. Sed를 사용하여 HTML 텍스트/HTML 테이블 영역 치환 (줄바꿈이 없는 변수)
# 구분자로 ~ 사용
sed -i.bak "s~__AI_PREDICTION__~$ai_prediction~g" index.html
sed -i.bak "s~__DAILY_TABLE_HTML__~$daily_table~g" index.html
sed -i.bak "s~__HOURLY_TABLE_HTML__~$hourly_table~g" index.html
sed -i.bak "s~__LAST_UPDATE_TIME__~$LAST_UPDATE_TIME~g" index.html

# 4.2. AWK를 사용하여 JavaScript 변수 치환 (멀티라인 데이터, 가장 중요한 부분)
# RAW_DATA_FOR_JS (result.txt의 전체 내용)를 백틱(` `) 안에 안전하게 삽입합니다.
awk -v data_to_insert="$RAW_DATA_FOR_JS" '
    BEGIN {
        # AWK의 -v 옵션을 통해 전달된 문자열은 줄바꿈이 그대로 살아있습니다.
        # 이스케이프가 필요 없으므로, 문자열 그대로 REPLACEMENT에 저장합니다.
        # 치환할 원본 문자열 패턴.
        TARGET_PATTERN = "const RAW_DATA_CONTENT = `RAW_DATA_PLACEHOLDER_FOR_JS`;"
        REPLACEMENT = "const RAW_DATA_CONTENT = `" data_to_insert "`;";
    }
    {
        # 파일 전체를 순회하며 치환
        sub(TARGET_PATTERN, REPLACEMENT);
        print;
    }
' index.html > index.html.tmp && mv index.html.tmp index.html

# 4.3. 정리 및 결과 출력
rm index.html.bak 2>/dev/null
echo "4.4. index.html 파일 생성 완료. 파일 크기: $(wc -c < index.html) 바이트"

