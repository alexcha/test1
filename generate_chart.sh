# 이 스크립트는 result.txt 파일을 읽어 html 대시보드를 생성합니다.



# 🚨 1. 환경 변수 설정 (github actions 환경 변수 이름과 일치시킴)
# github actions의 ${{ secrets.gkey }}가 env: gemini_api_key로 매핑되어 전달됩니다.
gemini_api_key="$gemini_api_key" 

# 오류 체크: api 키가 비어있는지 셸에서 사전 체크
if [ -z "$gemini_api_key" ]; then
    echo "오류: 환경 변수 gemini_api_key가 설정되지 않았습니다. github actions의 secret(gkey) 및 env: 매핑을 확인하세요." >&2
fi


# 1. 데이터 파싱 (차트용 데이터: 변화 값 - 시간 순서대로)
# js_values: 누적값이 아닌, 직전 값과의 '변화 값' 리스트를 생성합니다. (첫 번째 데이터의 변화는 0)
# ⭐️ 변경: 변화가 0인 모든 데이터 포인트는 필터링하여 제외합니다. (요청에 따라)
js_values=$(awk -F ' : ' '
    { 
        # 쉼표 제거 후 숫자값으로 변환
        gsub(/,/, "", $2); 
        all_values[nr] = $2 + 0; # nr starts at 1
    }
    end {
        # 첫 번째 데이터 포인트의 변화는 0으로 처리 (시작점). 
        # 이 포인트는 항상 포함합니다.
        filtered_changes[1] = 0; 
        filtered_index = 1;
        
        # iterate from the second point
        for (i = 2; i <= nr; i++) {
            change = all_values[i] - all_values[i-1];
            
            # ⭐️ 핵심 수정: 변화가 0이 아닐 경우에만 기록 (상승 또는 하락)
            if (change != 0) {
                filtered_index++;
                filtered_changes[filtered_index] = change;
            } 
            # 변화가 0일 경우, 연속 여부에 상관없이 모두 건너뜁니다.
        }

        # 변화값 출력
        for (j = 1; j <= filtered_index; j++) {
            printf "%s", filtered_changes[j]
            if (j < filtered_index) {
                printf ", "
            }
        }
    }
' result.txt) 

# js_labels: 시간 레이블을 "월-일 시" 형식 (mm-dd hh시)으로 포맷합니다.
# ⭐️ 변경: js_values와 동기화하여 변화가 0인 모든 시점의 레이블은 제외합니다.
js_labels=$(awk -F ' : ' '
    { 
        gsub(/,/, "", $2); 
        all_values[nr] = $2 + 0;
        
        # $1 format is yyyy-mm-dd hh:mm:ss. extract mm-dd hh시
        formatted_label = substr($1, 6, 5) " " substr($1, 12, 2) "시";
        all_labels[nr] = formatted_label;
    }
    end {
        filtered_labels[1] = all_labels[1]; # 첫 번째 레이블은 포함
        filtered_index = 1;
        
        for (i = 2; i <= nr; i++) {
            change = all_values[i] - all_values[i-1];
            
            # ⭐️ 핵심 수정: 변화가 0이 아닐 경우에만 레이블을 기록
            if (change != 0) {
                filtered_index++;
                filtered_labels[filtered_index] = all_labels[i];
            }
        }

        for (j = 1; j <= filtered_index; j++) {
            printf "\"%s\"", filtered_labels[j]
            if (j < filtered_index) {
                printf ", "
            }
        }
    }
' result.txt) 

# 2. 메인 html 테이블 row 데이터 생성 (js 페이지네이션을 위해 <tr> 태그만 생성)
# ⭐️ 변경: raw_table_rows 생성 시에도 변화가 0인 항목을 제외합니다.
raw_table_rows=$(awk -F ' : ' '
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
        # 절대값 s를 쉼표 포맷
        abs_s = (s < 0) ? -s : s;
        abs_s_str = abs_s ""; 
        result = "";
        while (abs_s_str ~ /[0-9]{4}/) {
            result = "," substr(abs_s_str, length(abs_s_str)-2) result;
            abs_s_str = substr(abs_s_str, 1, length(abs_s_str)-3);
        }
        return sign abs_s_str result;
    } 

    {
        # $1 format is yyyy-mm-dd hh:mm:ss
        formatted_time[nr] = substr($1, 6, 5) " " substr($1, 12, 2) "시";
        
        values_str[nr] = $2;
        gsub(/,/, "", $2); 
        values_num[nr] = $2 + 0; 
    }
    end {
        # nr: total number of records. loop backwards (newest first).
        for (i = nr; i >= 1; i--) {
            current_val_num = values_num[i]; 

            if (i > 1) {
                prev_val_num = values_num[i - 1];
                diff = current_val_num - prev_val_num;
                
                # ⭐️ 핵심 수정: 변화가 0인 경우, 이 행 전체를 건너뜁니다.
                if (diff == 0 && i != 1) { 
                    continue; 
                }
                
                if (diff != 0) {
                    diff_display = comma_format(diff); 

                    if (diff > 0) {
                        color_style = "color: #dc3545; font-weight: 600;";
                    } else if (diff < 0) {
                        color_style = "color: #007bff; font-weight: 600;";
                    }
                } else if (i == 1) {
                    # 원본 데이터의 가장 오래된 기록은 변화가 '---'입니다. (역순 루프에서 가장 마지막)
                    diff_display = "---";
                    color_style = "color: #6c757d;";
                }
            } else {
                # 루프의 마지막 실행 (가장 오래된 데이터)
                diff_display = "---";
                color_style = "color: #6c757d;";
            } 

            # 이 코드는 nr번째 데이터부터 1번째 데이터까지 역순으로 출력합니다.
            printf "<tr>\
                <td style=\"padding: 8px; border-top: 1px solid #eee; border-right: 1px solid #eee; text-align: left; background-color: white; font-size: 14px; color: #343a40;\">%s</td>\
                <td style=\"padding: 8px; border-top: 1px solid #eee; border-right: 1px solid #eee; text-align: right; background-color: white; font-weight: 600; color: #333; font-size: 14px;\">%s</td>\
                <td style=\"padding: 8px; border-top: 1px solid #eee; text-align: right; background-color: white; font-size: 14px; %s\">%s</td>\
            </tr>\n", formatted_time[i], values_str[i], color_style, diff_display
        }
    }
' result.txt) 

# 3. 일별 집계 테이블 생성 (awk에서 너비 설정 제거)
daily_summary_table=$(awk -F ' : ' '
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
    end {
        for (i = 0; i < num_dates; i++) {
            for (j = i + 1; j < num_dates; j++) {
                if (dates_arr[i] > dates_arr[j]) {
                    temp = dates_arr[i];
                    dates_arr[i] = dates_arr[j];
                    dates_arr[j] = temp;
                }
            }
        } 

        # max-width, min-width 제거 (css 클래스가 제어)
        # 테이블 전체 폰트 사이즈를 14px로 통일
        print "<table style=\"width: 100%; border-collapse: separate; border-spacing: 0; border: 1px solid #ddd; font-size: 14px; border-radius: 8px; overflow: hidden; margin-top: 20px; table-layout: fixed;\">";
        # 각 열의 너비를 비율로 지정
        print "<colgroup>\
            <col style=\"width: 33%;\">\
            <col style=\"width: 37%;\">\
            <col style=\"width: 30%;\">\
        </colgroup>";
        # th padding: 8px로 수정
        print "<thead><tr>\
            <th style=\"padding: 8px; background-color: white; border-right: 1px solid #ccc; text-align: left; color: #333;\">날짜</th>\
            <th style=\"padding: 8px; background-color: white; border-right: 1px solid #ccc; text-align: right; color: #333;\">값</th>\
            <th style=\"padding: 8px; background-color: white; text-align: right; color: #333;\">변화</th>\
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
            
            # td padding: 8px, font-size: 14px (숫자 폰트 크기 일관성 유지)
            row_data[i] = sprintf("<tr>\
                <td style=\"padding: 8px; border-top: 1px solid #eee; border-right: 1px solid #eee; text-align: left; background-color: white; color: #343a40; font-size: 14px;\">%s</td>\
                <td style=\"padding: 8px; border-top: 1px solid #eee; border-right: 1px solid #eee; text-align: right; background-color: white; font-weight: 600; color: #333; font-size: 14px;\">%s</td>\
                <td style=\"padding: 8px; border-top: 1px solid #eee; text-align: right; background-color: white; font-size: 14px; %s\">%s</td>\
            </tr>", date, current_value_display, color_style, diff_display); 

            prev_value = current_value;
        } 

        for (i = num_dates - 1; i >= 0; i--) {
            print row_data[i];
        } 

        print "</tbody></table>";
    }
' result.txt) 

# 3-1. 일별 집계 차트용 값 파싱 (js_daily_values - 변경 없음)
js_daily_values=$(awk -F ' : ' '
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
    end {
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

# 3-2. 일별 집계 차트용 레이블 파싱 (js_daily_labels - 변경 없음)
js_daily_labels=$(awk -F ' : ' '
    {
        date = substr($1, 1, 10);
        if (!(date in added_dates)) {
            dates_arr[num_dates++] = date;
            added_dates[date] = 1;
        }
    }
    end {
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

# 4. ai 예측용 원본 데이터 문자열 (프롬프트에 삽입 - 변경 없음)
raw_data_prompt_content=$(awk '
    {
        gsub(/"/, "\\\"", $0);
        output = output $0 "\\n";
    }
    end {
        sub(/\\n$/, "", output);
        print output;
    }
' result.txt)


# --- 5. ai 예측 로직 (스크립트 실행 시 자동 호출 - 변경 없음) ---

model="gemini-2.5-flash"
api_url="https://generativelanguage.googleapis.com/v1beta/models/${model}:generatecontent?key=${gemini_api_key}"

# 다음 날짜를 계산합니다.
last_data_date=$(tail -n 1 result.txt | awk -F ' : ' '{print $1}' | cut -d ' ' -f 1)
target_date=$(date -d "$last_data_date + 1 day" +%Y-%m-%d)

# 현재 월의 마지막 날짜 (월말)를 계산합니다.
year_month=$(date -d "$last_data_date" +%Y-%m)
# 다음 달 1일에서 하루를 빼서 현재 월의 마지막 날을 구합니다.
end_of_month_date=$(date -d "$year_month-01 + 1 month - 1 day" +%Y-%m-%d)

# json 페이로드에 들어갈 내용을 이스케이프하는 함수
escape_json() {
    # 1. 백슬래시를 먼저 이스케이프 (json 문자열에서 백슬래시는 \\로 표현)
    # 2. 큰따옴표를 이스케이프 (\"로 표현)
    # 3. 개행 문자를 json 이스케이프 문자열로 변환 (\n으로 표현)
    echo "$1" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | sed ':a;n;s/\n/\\n/g;ta'
}


# system_prompt: contextual_priority와 모바일 게임 맥락을 모두 포함
system_prompt="**핵심 고려 사항: ${contextual_priority}**\n**데이터 맥락: 분석하는 데이터는 10월 28일에 오픈한 모바일 게임의 누적 매출 데이터입니다. (단위: 달러)**\n\n당신은 전문 데이터 분석가입니다. 제공된 시계열 누적 데이터를 분석하고, 다음 세 가지 핵심 정보를 포함하여 **최대 3문장 이내**로 응답하세요: 1) **현재 일별 변화 추이(상승, 하락, 횡보)**, 2) **다음 날(${target_date})의 예상 최종 누적 값**, 3) **이달 말(${end_of_month_date})의 예상 최종 누적 값**. 불필요한 서론/결론, 목록, 표는 절대 포함하지 마세요. 추정치임을 명시해야 합니다."

# user_query: 불필요한 설명 제거 및 간소화
user_query="다음은 시계열 누적 데이터입니다. 이 데이터를 분석하여 **${target_date}**와 **${end_of_month_date}**의 예상 누적 값을 예측해주세요.\\n\\n데이터:\\n${raw_data_prompt_content}"

json_system_prompt=$(escape_json "$system_prompt")
json_user_query=$(escape_json "$user_query")

payload='{
    "contents": [{ "parts": [{ "text": "'"$json_user_query"'" }] }],
    "systeminstruction": { "parts": [{ "text": "'"$json_system_prompt"'" }] },
    "tools": [{ "google_search": {} }]
}'

# ai 예측 헤더 업데이트
prediction_header_embed="AI 기반 추이 분석 및 예측: ${target_date} 및 ${end_of_month_date}"
# 기본값: 키 없음 오류 메시지 (error-message 클래스 사용)
prediction_text_embed='<div class="error-message"><span style="font-weight: 700;">⚠️ 오류: API 키 없음.</span> 환경 변수 gemini_api_key가 설정되지 않아 예측을 실행할 수 없습니다. github actions의 secret(gkey) 및 워크플로우 변수 매핑을 확인하세요.</div>' 

if [ -n "$gemini_api_key" ]; then
    # curl 호출 및 응답 획득 (출력은 stderr로 리다이렉트)
    api_response=$(curl -s -X POST -H "Content-Type: application/json" -H "Accept: application/json" "$api_url" -d "$payload" 2>/dev/null)
    curl_status=$?

    if [ $curl_status -ne 0 ]; then
        prediction_text_embed="<div class=\"error-message\"><span style=\"font-weight: 700;\">❌ API 호출 실패.</span> curl 상태 코드: $curl_status. 네트워크 연결 또는 API 서버 상태를 확인하세요.</div>"
        prediction_header_embed="AI 기반 추이 분석 및 예측 (curl 오류)"
    elif echo "$api_response" | grep -q '"error":'; then
        # API 오류 메시지 추출
        error_message=$(echo "$api_response" | grep -o '"message": "[^"]*"' | head -n 1 | sed 's/"message": "//; s/"$//')
        prediction_text_embed="<div class=\"error-message\"><span style=\"font-weight: 700;\">⚠️ 예측 결과 실패.</span> API 오류: ${error_message}</div>"
        prediction_header_embed="AI 기반 추이 분석 및 예측 (API 오류)"
    else
        # jq를 사용하여 안정적으로 JSON 파싱 및 텍스트 추출
        raw_text_content=$(echo "$api_response" | jq -r '.candidates[0].content.parts[0].text // ""' 2>/dev/null)

        if [ -z "$raw_text_content" ]; then
            # 텍스트가 비어있을 경우, 블록킹 사유를 확인하여 더 자세한 오류 메시지를 제공
            block_reason=$(echo "$api_response" | jq -r '.candidates[0].finishReason // .promptFeedback.blockReason // ""' 2>/dev/null)
            
            if [ -n "$block_reason" ]; then
                 prediction_text_embed="<div class=\"error-message\"><span style=\"font-weight: 700;\">⚠️ 응답 필터링됨.</span> 응답 내용이 정책에 의해 차단되었거나 (finish reason: ${block_reason}) 누락되었습니다.</div>"
                 prediction_header_embed="AI 기반 추이 분석 및 예측 (차단 오류)"
            else
                 prediction_text_embed="<div class=\"error-message\"><span style=\"font-weight: 700;\">⚠️ 응답 파싱 실패.</span> 예측 텍스트를 파싱할 수 없습니다. 이는 API 응답 구조가 예상과 다르거나, \`jq\` 명령어를 찾을 수 없을 때 발생합니다.</div>"
                 prediction_header_embed="AI 기반 추이 분석 및 예측 (파싱 오류)"
            fi
        else
            # \n을 <br>로, \t를 공백으로 변환합니다.
            formatted_text=$(echo "$raw_text_content" | sed ':a;n;$!ba;s/\n/<br>/g' | sed 's/\t/&nbsp;&nbsp;&nbsp;&nbsp;/g')

            # 출처/grounding 정보 추출 (jq 사용)
            sources_html=""
            sources_array=$(echo "$api_response" | jq -r '.candidates[0].groundingMetadata.groundingAttributions[] | select(.web) | [.web.uri, .web.title] | @tsv' 2>/dev/null)
            
            if [ -n "$sources_array" ]; then
                first_source=$(echo "$sources_array" | head -n 1)
                uri=$(echo "$first_source" | awk '{print $1}')
                title=$(echo "$first_source" | awk '{$1=""; print $0}' | xargs)

                if [ ! -z "$uri" ] && [ ! -z "$title" ]; then
                    sources_html="<div class=\"sources-container\">
                        <p style=\"font-size: 12px; color: #555; margin-bottom: 5px;\">출처 (Google Search):</p>
                        <p style=\"font-size: 12px; margin: 2px 0;\"><a href=\"${uri}\" target=\"_blank\" style=\"color: #007bff; text-decoration: none;\">${title}</a></p>
                    </div>"
                fi
            fi
            
            # 성공 메시지 (success-message 클래스 사용)
            prediction_text_embed="<div class=\"success-message\">${formatted_text}${sources_html}</div>"
        fi
    fi
fi

# 6. html 파일 생성 (money.html로 변경)
cat << chart_end > money.html
<!doctype html>
<html>
<head>
    <title>데이터 변화 추이 대시보드</title>
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;600;700&display=swap" rel="stylesheet">
    <script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.3/dist/chart.umd.min.js"></script>
    <style>
        /* 좌우 꽉 참 및 내용 대비 문제 해결 css */
        body { font-family: 'Inter', sans-serif; margin: 0; padding: 0; background-color: #f7f7f7; color: #333; }
        
        .container { 
            width: 95%; /* 사용자가 요청한 95% 너비로 수정 */
            max-width: 1400px; 
            margin: 0 auto; 
            padding: 10px; /* 내부 여백 최소화 */
            background: white; 
            border-radius: 0; 
            box-shadow: none; 
        }
        
        h1 { text-align: center; color: #333; margin-bottom: 5px; font-size: 26px; font-weight: 700; }
        p.update-time { text-align: center; color: #777; margin-bottom: 20px; font-size: 14px; }
        
        .chart-container { 
            margin-bottom: 30px; 
            border: 1px solid #eee; 
            border-radius: 8px; 
            padding: 15px; 
            background: #fff; 
            height: 40vh; 
            min-height: 300px; 
            box-shadow: 0 4px 8px rgba(0, 0, 0, 0.05);
            position: relative; 
        }
        
        h2 { 
            margin-top: 30px; 
            margin-bottom: 10px; 
            text-align: center; 
            color: #343a40; 
            font-size: 22px; 
            font-weight: 600;
            border-bottom: 2px solid #343a40; 
            padding-bottom: 8px; 
            display: inline-block;
            width: auto;
            margin-left: auto;
            margin-right: auto;
        }
        
        #daily-chart-header, #daily-summary-chart-header { /* daily-summary-chart-header 추가 */
            margin-top: 40px !important; 
        }
        
        /* AI 예측 섹션 스타일 */
        .prediction-section {
            padding: 20px;
            margin-bottom: 30px; 
            background-color: #f0f8ff; 
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
        
        /* 오류 메시지 스타일: 대비 강화 */
        .error-message {
            text-align: left;
            padding: 15px;
            background-color: #ffe0e6; 
            border: 1px solid #dc3545; 
            color: #dc3545; 
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
            color: #333; 
        }
        
        .sources-container {
             margin-top: 20px; 
             border-top: 1px solid #eee; 
             padding-top: 10px;
        }
        
        /* 데이터 없음 메시지 스타일 */
        .no-data-message {
             position: absolute; 
             top: 50%;
             left: 50%;
             transform: translate(-50%, -50%);
             text-align: center; 
             color: #6c757d; 
             padding: 20px; 
             font-size: 16px;
             font-weight: 600;
             width: 80%; 
        }

        /* --- 페이지네이션 및 테이블 스타일 --- */
        .pagination-controls {
            display: flex;
            justify-content: center;
            align-items: center;
            margin-top: 15px;
            margin-bottom: 40px;
            gap: 10px;
        }
        .pagination-button {
            background-color: #007bff;
            color: white;
            border: none;
            padding: 8px 15px;
            border-radius: 6px;
            cursor: pointer;
            transition: background-color 0.2s, opacity 0.2s;
            font-weight: 600;
        }
        .pagination-

