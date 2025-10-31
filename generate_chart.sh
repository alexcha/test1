#!/bin/bash
#
# 1. 데이터 파싱 (차트용 데이터: 시간 순서대로)

# JS_VALUES: 쉼표로 구분된 값 (차트 데이터용)
# NOTE: 차트 생성을 위해 쉼표(,)를 제거한 숫자형 배열로 변환
JS_VALUES=$(awk -F ' : ' '
    { 
        # 값에서 쉼표(,) 제거
        gsub(/,/, "", $2); 
        values[i++] = $2
    }
    END {
        # 배열의 요소를 ", "로 연결하여 출력
        for (j=0; j<i; j++) {
            printf "%s", values[j]
            if (j < i-1) {
                printf ", "
            }
        }
    }
' result.txt)

# JS_LABELS: 따옴표로 감싸고 쉼표로 구분된 시간 (차트 레이블용)
# NOTE: 시간 문자열에서 HH:MM 부분만 추출
JS_LABELS=$(awk -F ' : ' '
    { 
        # HH:MM 부분만 추출 (예: "23:29")
        match($1, /[0-9]{2}:[0-9]{2}/, short_label_arr);
        short_label = short_label_arr[0];
        labels[i++] = "\"" short_label "\""
    }
    END {
        # 배열의 요소를 ", "로 연결하여 출력
        for (j=0; j<i; j++) {
            printf "%s", labels[j]
            if (j < i-1) {
                printf ", "
            }
        }
    }
' result.txt)

# 2. HTML 테이블 생성 (차이값 계산 및 역순 정렬 로직 포함)
# Awk를 사용하여 파일을 읽고, 데이터를 배열에 저장하며, 역순으로 순회하여 차이값을 계산하고 HTML을 생성합니다.
HTML_TABLE_ROWS=$(awk -F ' : ' '
    # 초기화 및 데이터 저장
    {
        # $1: 시간 문자열, $2: 값 문자열 (쉼표 포함)
        times[NR] = $1;
        values_str[NR] = $2;
        
        # 값에서 쉼표(,) 제거 후 숫자형으로 저장
        gsub(/,/, "", $2); 
        values_num[NR] = $2 + 0; 
    }
    END {
        # 테이블 스타일 및 헤더 정의 (새로운 '변화' 컬럼 추가)
        print "<table style=\"width: 100%; max-width: 1000px; border-collapse: separate; border-spacing: 0; border: 1px solid #ddd; font-size: 14px; min-width: 300px; border-radius: 8px; overflow: hidden;\">";
        print "<thead><tr>\
            <th style=\"padding: 14px; background-color: #f8f9fa; border-right: 1px solid #ddd; text-align: left; color: #495057;\">시간 (KST)</th>\
            <th style=\"padding: 14px; background-color: #f8f9fa; border-right: 1px solid #ddd; text-align: right; color: #007bff;\">값</th>\
            <th style=\"padding: 14px; background-color: #f8f9fa; text-align: right; color: #495057;\">변화</th>\
        </tr></thead>";
        print "<tbody>";

        # 역순으로 순회 (최신 데이터부터 출력)
        # i: 현재 행 번호 (NR), i-1: 이전 행 번호
        for (i = NR; i >= 1; i--) {
            time_str = times[i];
            current_val_str = values_str[i]; 
            current_val_num = values_num[i];

            # 이전 값 (i-1)이 존재하는 경우에만 차이 계산
            if (i > 1) {
                prev_val_num = values_num[i - 1];
                # 차이 = 현재 값 (신규) - 이전 값 (구형)
                diff = current_val_num - prev_val_num;

                # 변화값 포맷팅 및 스타일 결정
                if (diff > 0) {
                    # 쉼표 포맷팅을 위해 Awk의 문자열 함수 사용 (Locale 설정이 복잡하므로 간단히 표시)
                    diff_display = sprintf("+%,d", diff);
                    color_style = "color: #28a745; font-weight: 600;"; /* Green: 상승 */
                } else if (diff < 0) {
                    diff_display = sprintf("%,d", diff); 
                    color_style = "color: #dc3545; font-weight: 600;"; /* Red: 하락 */
                } else {
                    diff_display = "0";
                    color_style = "color: #6c757d;"; /* Gray: 변화 없음 */
                }
            } else {
                # 가장 오래된 데이터 (테이블에서 마지막 행)
                diff_display = "---";
                color_style = "color: #6c757d;";
            }

            # HTML 행 출력
            printf "<tr>\
                <td style=\"padding: 12px; border-top: 1px solid #eee; border-right: 1px solid #eee; text-align: left; background-color: white;\">%s</td>\
                <td style=\"padding: 12px; border-top: 1px solid #eee; border-right: 1px solid #eee; text-align: right; font-weight: bold; color: #007bff; background-color: white;\">%s</td>\
                <td style=\"padding: 12px; border-top: 1px solid #eee; text-align: right; background-color: white; %s\">%s</td>\
            </tr>\n", time_str, current_val_str, color_style, diff_display
        }
        
        print "</tbody></table>";
    }
' result.txt)

# 3. HTML 파일 생성 (index.html)

cat << CHART_END > index.html
<!DOCTYPE html>
<html>
<head>
    <title>데이터 변화 추이 대시보드</title>
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;600;700&display=swap" rel="stylesheet">
    <!-- Chart.js CDN 링크 -->
    <script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.3/dist/chart.umd.min.js"></script>
    <style>
        body { font-family: 'Inter', sans-serif; margin: 0; background-color: #f7f7f7; color: #333; }
        .container { width: 95%; max-width: 1000px; margin: 20px auto; padding: 20px; background: white; border-radius: 12px; box-shadow: 0 8px 16px rgba(0, 0, 0, 0.1); }
        h1 { text-align: center; color: #333; margin-bottom: 5px; font-size: 26px; font-weight: 700; }
        p.update-time { text-align: center; color: #777; margin-bottom: 30px; font-size: 14px; }
        /* 차트 컨테이너가 모바일에서 너무 작아지지 않도록 최소 높이 설정 */
        #chartContainer { 
            margin-bottom: 50px; 
            border: 1px solid #eee; 
            border-radius: 8px; 
            padding: 15px; 
            background: #fff; 
            /* 반응형 높이를 위해 vh 사용 */
            height: 40vh; 
            min-height: 300px; 
            box-shadow: 0 4px 8px rgba(0, 0, 0, 0.05);
        }
        h2 { 
            margin-top: 40px; 
            margin-bottom: 15px; 
            text-align: center; 
            color: #007bff; 
            font-size: 22px; 
            font-weight: 600;
            border-bottom: 2px solid #007bff; 
            padding-bottom: 10px;
            display: inline-block;
            width: auto;
            margin-left: auto;
            margin-right: auto;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>데이터 변화 추이</h1>
        <p class="update-time">최근 업데이트 시간: $(tail -n 1 result.txt | awk -F ' : ' '{print $1}')</p>
        
        <!-- 차트 영역 -->
        <div id="chartContainer">
            <canvas id="simpleChart"></canvas>
        </div>
        
        <!-- 데이터 표 영역 -->
        <div style="text-align: center;">
            <h2>데이터 기록 (최신순)</h2>
        </div>
        <div>
            ${HTML_TABLE_ROWS}
        </div>
    </div>
    
    <script>
    // 🚨 셸 스크립트에서 파싱된 동적 데이터가 여기에 삽입됩니다.
    const chartData = [${JS_VALUES}];
    const chartLabels = [${JS_LABELS}];

    console.log("Chart Data Array:", chartData);
    console.log("Chart Labels Array:", chartLabels);

    const ctx = document.getElementById('simpleChart').getContext('2d');
    
    if (chartData.length === 0) {
        console.error("Chart data is empty. Cannot render chart.");
        document.getElementById('chartContainer').innerHTML = "<p style='text-align: center; color: #dc3545; padding: 50px; font-size: 16px;'>데이터가 없어 차트를 그릴 수 없습니다.</p>";
    } else {
        new Chart(ctx, {
            type: 'line',
            data: {
                labels: chartLabels,
                datasets: [{
                    label: '값 변화 추이',
                    data: chartData,
                    borderColor: '#007bff', /* 파란색으로 변경 */
                    backgroundColor: 'rgba(0, 123, 255, 0.2)', /* 투명도 있는 파란색 */
                    borderWidth: 2,
                    tension: 0.4, /* 곡선 부드럽게 */
                    pointRadius: 4,
                    pointBackgroundColor: '#007bff',
                    pointHoverRadius: 6,
                    fill: 'start' // 차트 아래를 채움
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false, // 컨테이너 크기에 맞춤
                scales: {
                    x: {
                        type: 'category', 
                        title: { display: true, text: '시간 (HH:MM)', font: { size: 14, weight: 'bold' } },
                        ticks: {
                            // 🚨 데이터가 늘어날 때 X축 레이블 겹침 방지 전략
                            maxRotation: 45, // 최대 45도 회전 허용 (모바일 가독성 확보)
                            minRotation: 45, // 45도 회전 강제
                            autoSkip: true,  // Chart.js가 자동으로 레이블을 건너뛰도록 설정
                            maxTicksLimit: 25, // 표시할 최대 레이블 수 (데이터 밀도에 따라 유동적)
                            font: { size: 12 }
                        }
                    },
                    y: {
                        title: { display: true, text: '값', font: { size: 14, weight: 'bold' } },
                        beginAtZero: false,
                        grid: {
                            color: 'rgba(0, 0, 0, 0.05)',
                        },
                        ticks: {
                            // Y축 값에 쉼표(,) 추가
                            callback: function(value) {
                                return value.toString().replace(/\B(?=(\d{3})+(?!\d))/g, ",");
                            }
                        }
                    }
                },
                plugins: {
                    legend: {
                        display: false
                    },
                    tooltip: {
                        mode: 'index',
                        intersect: false,
                        bodyFont: { size: 14 },
                        callbacks: {
                            label: function(context) {
                                let label = context.dataset.label || '';
                                if (label) {
                                    label += ': ';
                                }
                                if (context.parsed.y !== null) {
                                    // 툴팁 값에도 쉼표(,) 추가
                                    label += context.parsed.y.toString().replace(/\B(?=(\d{3})+(?!\d))/g, ",");
                                }
                                return label;
                            }
                        }
                    },
                    title: {
                        display: true,
                        text: '값 변화 추이 (Chart.js)',
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