#!/bin/bash
# 이 스크립트는 result.txt 파일을 읽어 HTML 대시보드를 생성합니다.

# 🚨 1. 환경 변수 설정 (GitHub Actions 환경 변수 이름과 일치시킴)
# GitHub Actions의 ${{ secrets.GKEY }}가 env: GEMINI_API_KEY로 매핑되어 전달됩니다.
GEMINI_API_KEY="$GEMINI_API_KEY" 

# 오류 체크: API 키가 비어있는지 셸에서 사전 체크
if [ -z "$GEMINI_API_KEY" ]; then
    echo "오류: 환경 변수 GEMINI_API_KEY가 설정되지 않았습니다. GitHub Actions의 Secret(GKEY) 및 env: 매핑을 확인하세요." >&2
fi


# 1. 데이터 파싱 (차트용 데이터: 변화 값 - 시간 순서대로)
# 누적값이 아닌, 직전 값과의 '변화 값' 리스트를 생성합니다. (첫 번째 데이터의 변화는 0)
JS_VALUES=$(awk -F ' : ' '
    { 
        # 쉼표 제거 후 숫자값으로 변환
        gsub(/,/, "", $2); 
        values[NR] = $2 + 0; # NR starts at 1
    }
    END {
        # 변화값 배열
        change_values[1] = 0; # 첫 번째 데이터 포인트의 변화는 0으로 처리 (시작점)
        
        for (i = 2; i <= NR; i++) {
            # 변화값 = 현재 값 - 이전 값
            change_values[i] = values[i] - values[i-1];
        }

        # 변화값 출력
        for (j = 1; j <= NR; j++) {
            printf "%s", change_values[j]
            if (j < NR) {
                printf ", "
            }
        }
    }
' result.txt) 

# JS_LABELS: 따옴표로 감싸고 쉼표로 구분된 시간 (차트 레이블용 - 변경 없음)
JS_LABELS=$(awk -F ' : ' '
    { 
        match($1, /[0-9]{2}:[0-9]{2}/, short_label_arr);
        short_label = short_label_arr[0];
        labels[i++] = "\"" short_label "\""
    }
    END {
        for (j=0; j<i; j++) {
            printf "%s", labels[j]
            if (j < i-1) {
                printf ", "
            }
        }
    }
' result.txt) 

# 2. 메인 HTML 테이블 생성 (차이값 계산 및 역순 정렬 로직 포함 - 변경 없음)
HTML_TABLE_ROWS=$(awk -F ' : ' '
    function comma_format(n) {
        if (n == 0) return "0";
        s = int(n);
        if (s > 0) {
            sign = "+";
        } else if (s < 0) {
            sign = "-";
            s = -s;    
        } else {
            sign = "";
        }
        s = s ""; 
        result = "";
        while (s ~ /[0-9]{4}/) {
            result = "," substr(s, length(s)-2) result;
            s = substr(s, 1, length(s)-3);
        }
        return sign s result;
    } 

    {
        times[NR] = $1;
        values_str[NR] = $2;
        gsub(/,/, "", $2); 
        values_num[NR] = $2 + 0; 
    }
    END {
        print "<table style=\"width: 100%; max-width: 1000px; border-collapse: separate; border-spacing: 0; border: 1px solid #ddd; font-size: 14px; min-width: 300px; border-radius: 8px; overflow: hidden;\">";
        print "<thead><tr>\
            <th style=\"padding: 14px; background-color: white; border-right: 1px solid #ccc; text-align: left; color: #333;\">시간</th>\
            <th style=\"padding: 14px; background-color: white; border-right: 1px solid #ccc; text-align: right; color: #333;\">값</th>\
            <th style=\"padding: 14px; background-color: white; text-align: right; color: #333;\">변화</th>\
        </tr></thead>";
        print "<tbody>"; 

        for (i = NR; i >= 1; i--) {
            time_str = times[i];
            current_val_str = values_str[i]; 
            current_val_num = values_num[i]; 

            if (i > 1) {
                prev_val_num = values_num[i - 1];
                diff = current_val_num - prev_val_num;
                diff_display = comma_format(diff); 

                if (diff > 0) {
                    color_style = "color: #dc3545; font-weight: 600;";
                } else if (diff < 0) {
                    color_style = "color: #007bff; font-weight: 600;";
                } else {
                    diff_display = "0";
                    color_style = "color: #333; font-weight: 600;";
                }
            } else {
                diff_display = "---";
                color_style = "color: #6c757d;";
            } 

            printf "<tr>\
                <td style=\"padding: 12px; border-top: 1px solid #eee; border-right: 1px solid #eee; text-align: left; background-color: white;\">%s</td>\
                <td style=\"padding: 12px; border-top: 1px solid #eee; border-right: 1px solid #eee; text-align: right; font-weight: bold; color: #333; background-color: white;\">%s</td>\
                <td style=\"padding: 12px; border-top: 1px solid #eee; text-align: right; background-color: white; %s\">%s</td>\
            </tr>\n", time_str, current_val_str, color_style, diff_display
        }
        
        print "</tbody></table>";
    }
' result.txt) 

# 3. 일별 집계 테이블 생성 (변경 없음)
DAILY_SUMMARY_TABLE=$(awk -F ' : ' '
    function comma_format_sum_only(n) {
        if (n == 0) return "0";
        s = int(n);
        if (s < 0) { s = -s; }
        s = s ""; 
        result = "";
        while (s ~ /[0-9]{4}/) {
            result = "," substr(s, length(s)-2) result;
            s = substr(s, 1, length(s)-3);
        }
        return (int(n) < 0 ? "-" : "") s result;
    }
    
    function comma_format_diff_only(n) {
        if (n == 0) return "0";
        s = int(n);
        if (s > 0) { sign = "+"; } 
        else if (s < 0) { sign = "-"; s = -s; } 
        else { return "0"; }
        s = s ""; 
        result = "";
        while (s ~ /[0-9]{4}/) {
            result = "," substr(s, length(s)-2) result;
            s = substr(s, 1, length(s)-3);
        }
        return sign s result;
    } 

    {
        numeric_value = $2;
        gsub(/,/, "", numeric_value);
        date = substr($1, 1, 10);
        last_value[date] = numeric_value; 
        if (!(date in added_dates)) {
            dates_arr[num_dates++] = date;
            added_dates[date] = 1;
        }
    }
    END {
        for (i = 0; i < num_dates; i++) {
            for (j = i + 1; j < num_dates; j++) {
                if (dates_arr[i] > dates_arr[j]) {
                    temp = dates_arr[i];
                    dates_arr[i] = dates_arr[j];
                    dates_arr[j] = temp;
                }
            }
        } 

        print "<table style=\"width: 100%; max-width: 1000px; border-collapse: separate; border-spacing: 0; border: 1px solid #ddd; font-size: 14px; min-width: 300px; border-radius: 8px; overflow: hidden; margin-top: 20px;\">";
        print "<thead><tr>\
            <th style=\"padding: 14px; background-color: white; border-right: 1px solid #ccc; text-align: left; color: #333;\">날짜</th>\
            <th style=\"padding: 14px; background-color: white; border-right: 1px solid #ccc; text-align: right; color: #333;\">값</th>\
            <th style=\"padding: 14px; background-color: white; text-align: right; color: #333;\">변화</th>\
        </tr></thead>";
        print "<tbody>"; 

        prev_value = 0;
        
        for (i = 0; i < num_dates; i++) {
            date = dates_arr[i];
            current_value = last_value[date]; 

            diff = current_value - prev_value;
            current_value_display = comma_format_sum_only(current_value);
            
            if (i == 0) {
                diff_display = "---";
                color_style = "color: #6c757d;"; 
            } else {
                diff_display = comma_format_diff_only(diff);
                if (diff > 0) {
                    color_style = "color: #dc3545; font-weight: 600;";
                } else if (diff < 0) {
                    color_style = "color: #007bff; font-weight: 600;";
                } else {
                    diff_display = "0";
                    color_style = "color: #333; font-weight: 600;";
                }
            }
            
            row_data[i] = sprintf("<tr>\
                <td style=\"padding: 12px; border-top: 1px solid #eee; border-right: 1px solid #eee; text-align: left; background-color: white; color: #343a40;\">%s</td>\
                <td style=\"padding: 12px; border-top: 1px solid #eee; border-right: 1px solid #eee; text-align: right; background-color: white; font-weight: bold; color: #333;\">%s</td>\
                <td style=\"padding: 12px; border-top: 1px solid #eee; text-align: right; background-color: white; %s\">%s</td>\
            </tr>", date, current_value_display, color_style, diff_display); 

            prev_value = current_value;
        } 

        for (i = num_dates - 1; i >= 0; i--) {
            print row_data[i];
        } 

        print "</tbody></table>";
    }
' result.txt) 

# 3-1. 일별 집계 차트용 값 파싱 (JS_DAILY_VALUES - 변경 없음)
JS_DAILY_VALUES=$(awk -F ' : ' '
    {
        numeric_value = $2;
        gsub(/,/, "", numeric_value);
        date = substr($1, 1, 10);
        last_value[date] = numeric_value + 0;
        if (!(date in added_dates)) {
            dates_arr[num_dates++] = date;
            added_dates[date] = 1;
        }
    }
    END {
        for (i = 0; i < num_dates; i++) {
            for (j = i + 1; j < num_dates; j++) {
                if (dates_arr[i] > dates_arr[j]) {
                    temp = dates_arr[i];
                    dates_arr[i] = dates_arr[j];
                    dates_arr[j] = temp;
                }
            }
        }
        
        for (i = 0; i < num_dates; i++) {
            printf "%s", last_value[dates_arr[i]]
            if (i < num_dates - 1) {
                printf ", "
            }
        }
    }
' result.txt) 

# 3-2. 일별 집계 차트용 레이블 파싱 (JS_DAILY_LABELS - 변경 없음)
JS_DAILY_LABELS=$(awk -F ' : ' '
    {
        date = substr($1, 1, 10);
        if (!(date in added_dates)) {
            dates_arr[num_dates++] = date;
            added_dates[date] = 1;
        }
    }
    END {
        for (i = 0; i < num_dates; i++) {
            for (j = i + 1; j < num_dates; j++) {
                if (dates_arr[i] > dates_arr[j]) {
                    temp = dates_arr[i];
                    dates_arr[i] = dates_arr[j];
                    dates_arr[j] = temp;
                }
            }
        }
        
        for (i = 0; i < num_dates; i++) {
            printf "\"%s\"", dates_arr[i]
            if (i < num_dates - 1) {
                printf ", "
            }
        }
    }
' result.txt) 

# 4. AI 예측용 원본 데이터 문자열 (프롬프트에 삽입 - 변경 없음)
RAW_DATA_PROMPT_CONTENT=$(awk '
    {
        gsub(/"/, "\\\"", $0);
        output = output $0 "\\n";
    }
    END {
        sub(/\\n$/, "", output);
        print output;
    }
' result.txt)


# --- 5. 🚨 AI 예측 로직 (스크립트 실행 시 자동 호출 - 변경 없음) ---

MODEL="gemini-2.5-flash"
API_URL="https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent?key=${GEMINI_API_KEY}"

# 다음 날짜를 계산합니다.
LAST_DATA_DATE=$(tail -n 1 result.txt | awk -F ' : ' '{print $1}' | cut -d ' ' -f 1)
TARGET_DATE=$(date -d "$LAST_DATA_DATE + 1 day" +%Y-%m-%d)

# 현재 월의 마지막 날짜 (월말)를 계산합니다.
YEAR_MONTH=$(date -d "$LAST_DATA_DATE" +%Y-%m)
# 다음 달 1일에서 하루를 빼서 현재 월의 마지막 날을 구합니다.
END_OF_MONTH_DATE=$(date -d "$YEAR_MONTH-01 + 1 month - 1 day" +%Y-%m-%d)

# JSON 페이로드에 들어갈 내용을 이스케이프하는 함수
escape_json() {
    # 1. 백슬래시를 먼저 이스케이프 (JSON 문자열에서 백슬래시는 \\로 표현)
    # 2. 큰따옴표를 이스케이프 (\"로 표현)
    # 3. 개행 문자를 JSON 이스케이프 문자열로 변환 (\n으로 표현)
    echo "$1" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | sed ':a;N;s/\n/\\n/g;ta'
}


# 🚨 [수정된 부분] SYSTEM_PROMPT: CONTEXTUAL_PRIORITY와 모바일 게임 맥락을 모두 포함
SYSTEM_PROMPT="**핵심 고려 사항: ${CONTEXTUAL_PRIORITY}**\n**데이터 맥락: 분석하는 데이터는 10월 28일에 오픈한 모바일 게임의 누적 매출 데이터입니다. (단위: 달러)**\n\n당신은 전문 데이터 분석가입니다. 제공된 시계열 누적 데이터를 분석하고, 다음 세 가지 핵심 정보를 포함하여 **최대 3문장 이내**로 응답하세요: 1) **현재 일별 변화 추이(상승, 하락, 횡보)**, 2) **다음 날(${TARGET_DATE})의 예상 최종 누적 값**, 3) **이달 말(${END_OF_MONTH_DATE})의 예상 최종 누적 값**. 불필요한 서론/결론, 목록, 표는 절대 포함하지 마세요. 추정치임을 명시해야 합니다."

# 🚨 [수정된 부분] USER_QUERY: 불필요한 설명 제거 및 간소화
USER_QUERY="다음은 시계열 누적 데이터입니다. 이 데이터를 분석하여 **${TARGET_DATE}**와 **${END_OF_MONTH_DATE}**의 예상 누적 값을 예측해주세요.\\n\\n데이터:\\n${RAW_DATA_PROMPT_CONTENT}"

JSON_SYSTEM_PROMPT=$(escape_json "$SYSTEM_PROMPT")
JSON_USER_QUERY=$(escape_json "$USER_QUERY")

PAYLOAD='{
    "contents": [{ "parts": [{ "text": "'"$JSON_USER_QUERY"'" }] }],
    "systemInstruction": { "parts": [{ "text": "'"$JSON_SYSTEM_PROMPT"'" }] },
    "tools": [{ "google_search": {} }]
}'

# 🚨 [수정된 부분] AI 예측 헤더 업데이트
PREDICTION_HEADER_EMBED="AI 기반 추이 분석 및 예측: ${TARGET_DATE} 및 ${END_OF_MONTH_DATE}"
# 기본값: 키 없음 오류 메시지 (error-message 클래스 사용)
PREDICTION_TEXT_EMBED='<div class="error-message"><span style="font-weight: 700;">⚠️ 오류: API 키 없음.</span> 환경 변수 GEMINI_API_KEY가 설정되지 않아 예측을 실행할 수 없습니다. GitHub Actions의 Secret(GKEY) 설정 및 워크플로우 변수 매핑을 확인해주세요.</div>' 

if [ -n "$GEMINI_API_KEY" ]; then
    # curl 호출 및 응답 획득 (출력은 stderr로 리다이렉트)
    API_RESPONSE=$(curl -s -X POST -H "Content-Type: application/json" -H "Accept: application/json" "$API_URL" -d "$PAYLOAD" 2>/dev/null)
    CURL_STATUS=$?

    if [ $CURL_STATUS -ne 0 ]; then
        PREDICTION_TEXT_EMBED="<div class=\"error-message\"><span style=\"font-weight: 700;\">❌ API 호출 실패.</span> Curl 상태 코드: $CURL_STATUS. 네트워크 연결 또는 API 서버 상태를 확인하세요.</div>"
        PREDICTION_HEADER_EMBED="AI 기반 추이 분석 및 예측 (Curl 오류)"
    elif echo "$API_RESPONSE" | grep -q '"error":'; then
        # API 오류 메시지 추출
        ERROR_MESSAGE=$(echo "$API_RESPONSE" | grep -o '"message": "[^"]*"' | head -n 1 | sed 's/"message": "//; s/"$//')
        PREDICTION_TEXT_EMBED="<div class=\"error-message\"><span style=\"font-weight: 700;\">⚠️ 예측 결과 실패.</span> API 오류: ${ERROR_MESSAGE}</div>"
        PREDICTION_HEADER_EMBED="AI 기반 추이 분석 및 예측 (API 오류)"
    else
        # jq를 사용하여 안정적으로 JSON 파싱 및 텍스트 추출
        RAW_TEXT_CONTENT=$(echo "$API_RESPONSE" | jq -r '.candidates[0].content.parts[0].text // ""' 2>/dev/null)

        if [ -z "$RAW_TEXT_CONTENT" ]; then
            # 텍스트가 비어있을 경우, 블록킹 사유를 확인하여 더 자세한 오류 메시지를 제공
            BLOCK_REASON=$(echo "$API_RESPONSE" | jq -r '.candidates[0].finishReason // .promptFeedback.blockReason // ""' 2>/dev/null)
            
            if [ -n "$BLOCK_REASON" ]; then
                 PREDICTION_TEXT_EMBED="<div class=\"error-message\"><span style=\"font-weight: 700;\">⚠️ 응답 필터링됨.</span> 응답 내용이 정책에 의해 차단되었거나 (Finish Reason: ${BLOCK_REASON}) 누락되었습니다.</div>"
                 PREDICTION_HEADER_EMBED="AI 기반 추이 분석 및 예측 (차단 오류)"
            else
                 PREDICTION_TEXT_EMBED="<div class=\"error-message\"><span style=\"font-weight: 700;\">⚠️ 응답 파싱 실패.</span> 예측 텍스트를 파싱할 수 없습니다. 이는 API 응답 구조가 예상과 다르거나, \`jq\` 명령어를 찾을 수 없을 때 발생합니다.</div>"
                 PREDICTION_HEADER_EMBED="AI 기반 추이 분석 및 예측 (파싱 오류)"
            fi
        else
            # \n을 <br>로, \t를 공백으로 변환합니다.
            FORMATTED_TEXT=$(echo "$RAW_TEXT_CONTENT" | sed ':a;N;$!ba;s/\n/<br>/g' | sed 's/\t/&nbsp;&nbsp;&nbsp;&nbsp;/g')

            # 출처/Grounding 정보 추출 (jq 사용)
            SOURCES_HTML=""
            # groundingAttributions 배열에서 uri와 title을 TSV 형식으로 추출 (오류 무시)
            SOURCES_ARRAY=$(echo "$API_RESPONSE" | jq -r '.candidates[0].groundingMetadata.groundingAttributions[] | select(.web) | [.web.uri, .web.title] | @tsv' 2>/dev/null)
            
            # 첫 번째 출처만 사용
            if [ -n "$SOURCES_ARRAY" ]; then
                FIRST_SOURCE=$(echo "$SOURCES_ARRAY" | head -n 1)
                URI=$(echo "$FIRST_SOURCE" | awk '{print $1}')
                TITLE=$(echo "$FIRST_SOURCE" | awk '{$1=""; print $0}' | xargs) # URI를 제외한 나머지를 제목으로 사용

                if [ ! -z "$URI" ] && [ ! -z "$TITLE" ]; then
                    SOURCES_HTML="<div class=\"sources-container\">
                        <p style=\"font-size: 12px; color: #555; margin-bottom: 5px;\">출처 (Google Search):</p>
                        <p style=\"font-size: 12px; margin: 2px 0;\"><a href=\"${URI}\" target=\"_blank\" style=\"color: #007bff; text-decoration: none;\">${TITLE}</a></p>
                    </div>"
                fi
            fi
            
            # 성공 메시지 (success-message 클래스 사용)
            PREDICTION_TEXT_EMBED="<div class=\"success-message\">${FORMATTED_TEXT}${SOURCES_HTML}</div>"
        fi
    fi
fi

# 6. HTML 파일 생성 (index.html)
cat << CHART_END > index.html
<!DOCTYPE html>
<html>
<head>
    <title>데이터 변화 추이 대시보드</title>
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;600;700&display=swap" rel="stylesheet">
    <script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.3/dist/chart.umd.min.js"></script>
    <style>
        body { font-family: 'Inter', sans-serif; margin: 0; background-color: #f7f7f7; color: #333; }
        .container { width: 95%; max-width: 1000px; margin: 20px auto; padding: 20px; background: white; border-radius: 12px; box-shadow: 0 8px 16px rgba(0, 0, 0, 0.1); }
        h1 { text-align: center; color: #333; margin-bottom: 5px; font-size: 26px; font-weight: 700; }
        p.update-time { text-align: center; color: #777; margin-bottom: 30px; font-size: 14px; }
        /* 차트 컨테이너가 모바일에서 너무 작아지지 않도록 최소 높이 설정 */
        .chart-container { 
            margin-bottom: 50px; 
            border: 1px solid #eee; 
            border-radius: 8px; 
            padding: 15px; 
            background: #fff; 
            height: 40vh; 
            min-height: 300px; 
            box-shadow: 0 4px 8px rgba(0, 0, 0, 0.05);
        }
        /* h2 스타일: 두 제목 모두 검정색으로 통일 */
        h2 { 
            margin-top: 40px; 
            margin-bottom: 15px; 
            text-align: center; 
            color: #343a40; 
            font-size: 22px; 
            font-weight: 600;
            border-bottom: 2px solid #343a40; 
            padding-bottom: 10px;
            display: inline-block;
            width: auto;
            margin-left: auto;
            margin-right: auto;
        }
        /* 일일 집계 차트 제목 마진 조정 */
        #daily-chart-header {
            margin-top: 60px !important; 
        }
        
        /* --- AI 예측 섹션 스타일 개선 --- */
        .prediction-section {
            padding: 20px;
            margin-bottom: 40px;
            background-color: #f0f8ff; /* Light blue background for success section */
            border: 2px solid #007bff;
            border-radius: 12px;
            text-align: center;
        }
        .prediction-section h2 {
            color: #0056b3;
            margin-top: 0;
            border-bottom: none;
            padding-bottom: 0;
            font-size: 24px;
        }
        /* 오류 메시지 스타일 */
        .error-message {
            text-align: left;
            padding: 15px;
            background-color: #fcebeb; /* Light red for error */
            border: 1px solid #dc3545; /* Red border */
            color: #dc3545; /* Red text */
            border-radius: 8px;
            line-height: 1.6;
            font-size: 15px;
            margin-top: 20px;
        }
        /* 성공 메시지 컨테이너 */
        .success-message {
            text-align: left;
            padding: 15px;
            background-color: white;
            border: 1px solid #ccc;
            border-radius: 8px;
            min-height: 50px;
            font-size: 15px;
            line-height: 1.6;
            margin-top: 20px;
        }
        .sources-container {
             margin-top: 20px; 
             border-top: 1px solid #eee; 
             padding-top: 10px;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>데이터 변화 추이 대시보드</h1>
        <p class="update-time">최근 업데이트 시간: $(tail -n 1 result.txt | awk -F ' : ' '{print $1}')</p>
        
        <div class="prediction-section">
            <h2 id="prediction-header">${PREDICTION_HEADER_EMBED}</h2>
            <div id="predictionResult">
                ${PREDICTION_TEXT_EMBED}
            </div>
        </div>
        
        <div style="text-align: center;">
            <h2 id="daily-chart-header">일일 집계 추이</h2>
        </div>
        <div class="chart-container">
            <canvas id="dailyChart"></canvas>
        </div>
        
        <div style="text-align: center;">
            <h2>기록 시간별 변화 값 추이</h2>
        </div>
        <div class="chart-container">
            <canvas id="simpleChart"></canvas>
        </div> 

        
        <div style="text-align: center;">
            <h2>데이터 기록 (최신순)</h2>
        </div>
        <div>
            ${HTML_TABLE_ROWS}
        </div>
        
        <div style="text-align: center;">
            <h2>일일 집계 기록 (최신순)</h2>
        </div>
        <div>
            ${DAILY_SUMMARY_TABLE}
        </div> 
        
    </div>
    
    <script>
    // 🚨 셸 스크립트에서 파싱된 동적 데이터가 여기에 삽입됩니다.
    
    // 1. 시간별 상세 기록 데이터 (빨간색 차트 - 변화 값)
    const chartData = [${JS_VALUES}];
    const chartLabels = [${JS_LABELS}]; 

    // 2. 일별 최종 값 데이터 (파란색 차트 - 누적 값)
    const jsDailyValues = [${JS_DAILY_VALUES}];
    const jsDailyLabels = [${JS_DAILY_LABELS}]; 

    const formatYAxisTick = function(value) {
        if (value === 0) return '0';
        
        const absValue = Math.abs(value);
        let formattedValue; 

        // 음수와 양수 모두 처리하기 위해 절대값을 사용
        if (absValue >= 1000000000) {
            formattedValue = (value / 1000000000).toFixed(1).replace(/\.0$/, '') + 'B';
        } else if (absValue >= 1000000) {
            formattedValue = (value / 1000000).toFixed(1).replace(/\.0$/, '') + 'M';
        } else if (absValue >= 1000) {
            formattedValue = (value / 1000).toFixed(1).replace(/\.0$/, '') + 'K';
        } else {
            formattedValue = new Intl.NumberFormat('ko-KR').format(value);
        }
        return formattedValue;
    };
    
    const formatTooltip = function(context) {
        let label = context.dataset.label || '';
        if (label) {
            label += ': ';
        }
        if (context.parsed.y !== null) {
            // 변화값은 부호를 포함하여 포맷팅
            label += new Intl.NumberFormat('ko-KR', { signDisplay: context.dataset.label === '변화 값' ? 'always' : 'auto' }).format(context.parsed.y);
        }
        return label;
    };


    // ---------------------------------------------
    // 1. 차트 렌더링 로직 (simpleChart - 빨간색)
    // --------------------------------------------- 

    const ctx = document.getElementById('simpleChart').getContext('2d');
    
    if (chartData.length === 0) {
        console.error("Chart data is empty. Cannot render simpleChart.");
        document.getElementById('simpleChart').parentNode.innerHTML = "<p style='text-align: center; color: #dc3545; padding: 50px; font-size: 16px;'>데이터가 없어 차트를 그릴 수 없습니다.</p>";
    } else {
        new Chart(ctx, {
            // 변화값은 막대 그래프(bar)로 표현하는 것이 일반적이나, 
            // 기존과 동일한 line type을 유지하며 title/label만 변경합니다.
            type: 'line', 
            data: {
                labels: chartLabels,
                datasets: [{
                    label: '변화 값', // 레이블 변경
                    data: chartData,
                    borderColor: 'rgba(255, 99, 132, 1)',
                    backgroundColor: 'rgba(255, 99, 132, 0.4)', 
                    borderWidth: 3, 
                    tension: 0.4,
                    pointRadius: 4,
                    pointBackgroundColor: 'rgba(255, 99, 132, 1)', 
                    pointHoverRadius: 6,
                    fill: 'start'
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                scales: {
                    x: {
                        type: 'category', 
                        title: { display: true, text: '시간 (HH:MM)', font: { size: 14, weight: 'bold' } },
                        ticks: {
                            maxRotation: 45, 
                            minRotation: 45,
                            autoSkip: true,
                            maxTicksLimit: 25,
                            font: { size: 12 }
                        }
                    },
                    y: {
                        title: { display: true, text: '변화 값', font: { size: 14, weight: 'bold' } }, // Y축 제목 변경
                        beginAtZero: true, // 변화 값은 0을 기준으로 보는 것이 중요
                        grid: { color: 'rgba(0, 0, 0, 0.05)' },
                        ticks: { callback: formatYAxisTick }
                    }
                },
                plugins: {
                    legend: { display: false },
                    tooltip: {
                        mode: 'index',
                        intersect: false,
                        bodyFont: { size: 14 },
                        callbacks: { label: formatTooltip }
                    },
                    title: {
                        display: true,
                        text: '시간별 변화 값 추이 (HH:MM)', // 차트 제목 변경
                        font: { size: 18, weight: 'bold' },
                        padding: { top: 10, bottom: 10 }
                    }
                }
            }
        });
    } 

    // ---------------------------------------------
    // 2. 차트 렌더링 로직 (dailyChart - 파란색 - 변경 없음)
    // ---------------------------------------------
    const dailyCtx = document.getElementById('dailyChart').getContext('2d'); 

    if (jsDailyValues.length === 0) {
        console.error("Daily chart data is empty. Cannot render dailyChart.");
        document.getElementById('dailyChart').parentNode.innerHTML = "<p style='text-align: center; color: #007bff; padding: 50px; font-size: 16px;'>일일 집계 데이터가 없어 차트를 그릴 수 없습니다.</p>";
    } else {
        new Chart(dailyCtx, {
            type: 'line',
            data: {
                labels: jsDailyLabels,
                datasets: [{
                    label: '일일 최종 값',
                    data: jsDailyValues,
                    borderColor: 'rgba(0, 123, 255, 1)',
                    backgroundColor: 'rgba(0, 123, 255, 0.2)', 
                    borderWidth: 4, 
                    tension: 0.3, 
                    pointRadius: 6,
                    pointBackgroundColor: 'rgba(0, 123, 255, 1)', 
                    pointHoverRadius: 8,
                    fill: 'start' 
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                scales: {
                    x: {
                        type: 'category', 
                        title: { display: true, text: '날짜', font: { size: 14, weight: 'bold' } },
                        ticks: { font: { size: 12 } }
                    },
                    y: {
                        title: { display: true, text: '최종 값', font: { size: 14, weight: 'bold' } },
                        beginAtZero: false,
                        grid: { color: 'rgba(0, 0, 0, 0.05)' },
                        ticks: { callback: formatYAxisTick }
                    }
                },
                plugins: {
                    legend: { display: false },
                    tooltip: {
                        mode: 'index',
                        intersect: false,
                        bodyFont: { size: 14 },
                        callbacks: { label: formatTooltip }
                    },
                    title: {
                        display: true,
                        text: '일별 최종 값 변화 추이 (YYYY-MM-DD)',
                        font: { size: 18, weight: 'bold' },
                        padding: { top: 10, bottom: 10 }
                    }
                }
            }
        });
    }
    </script>
</body>
</html>
CHART_END