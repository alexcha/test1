#!/bin/bash

# 1. 데이터 파싱
# JS_VALUES: 쉼표로 구분된 값 (차트 데이터용)
JS_VALUES=$(awk -F ' : ' '{ 
    # 값에서 쉼표(,) 제거
    gsub(/,/, "", $2); 
    if (NR==1) {printf $2} else {printf ", %s", $2} 
}' result.txt | tr -d '\n' | sed 's/^[ \t]*//;s/[ \t]*$//')

# JS_LABELS: 따옴표로 감싸고 쉼표로 구분된 시간 (차트 레이블용)
JS_LABELS=$(awk -F ' : ' '{ 
    split($1, time_arr, " "); 
    short_label = time_arr[2] " " time_arr[3]; 
    if (NR==1) {printf "\"%s\"", short_label} else {printf ", \"%s\"", short_label} 
}' result.txt | tr -d '\n' | sed 's/^[ \t]*//;s/[ \t]*$//')

# 2. HTML 테이블 생성
# result.txt의 모든 데이터를 HTML <tr><td> 태그로 변환합니다.
HTML_TABLE_ROWS=$(awk -F ' : ' 'BEGIN {
    # 테이블 시작 및 스타일 정의
    print "<table style=\"width: 100%; max-width: 1000px; margin: 30px auto 0; border-collapse: collapse; border: 1px solid #ddd;\">";
    # 테이블 헤더
    print "<thead><tr><th style=\"padding: 12px; background-color: #f4f4f4; border: 1px solid #ddd; text-align: left;\">시간 (KST)</th><th style=\"padding: 12px; background-color: #f4f4f4; border: 1px solid #ddd; text-align: right;\">값</th></tr></thead>";
    print "<tbody>";
}
{
    # 데이터 행 (result.txt의 $1=시간, $2=값)
    printf "<tr><td style=\"padding: 10px; border: 1px solid #ddd; text-align: left;\">%s</td><td style=\"padding: 10px; border: 1px solid #ddd; text-align: right; font-weight: bold;\">%s</td></tr>\n", $1, $2
}
END {
    print "</tbody></table>";
}' result.txt)

# 3. HTML 파일 생성 (index.html)
cat << CHART_END > index.html
<!DOCTYPE html>
<html>
<head>
    <title>No..</title>
    <script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.3/dist/chart.umd.min.js"></script>
    <style>
        body { font-family: 'Inter', Arial, sans-serif; margin: 20px; background-color: #f7f7f7; color: #333; }
        .container { width: 95%; max-width: 1000px; margin: auto; padding: 20px; background: white; border-radius: 8px; box-shadow: 0 4px 6px rgba(0, 0, 0, 0.1); }
        h1 { text-align: center; color: #333; margin-bottom: 5px; }
        p.update-time { text-align: center; color: #777; margin-bottom: 20px; }
        #chartContainer { margin-bottom: 40px; }
        h2 { margin-top: 40px; margin-bottom: 10px; text-align: center; color: #555; }
        /* 표 스타일은 2. HTML 테이블 생성 섹션의 인라인 스타일로 정의됨 */
    </style>
</head>
<body>
    <div class="container">

        <p class="update-time">최근 업데이트 시간: $(tail -n 1 result.txt | awk -F ' : ' '{print $1}')</p>
        
        <div id="chartContainer">
            <canvas id="simpleChart"></canvas>
        </div>
        
        <h2>데이터 기록</h2>
        ${HTML_TABLE_ROWS} </div>
    
    <script>
    const chartData = [${JS_VALUES}];
    const chartLabels = [${JS_LABELS}];

    const ctx = document.getElementById('simpleChart').getContext('2d');
    
    if (chartData.length === 0) {
        console.error("Chart data is empty. Cannot render chart.");
        document.getElementById('chartContainer').innerHTML = "<p style='text-align: center; color: red;'>데이터가 없어 차트를 그릴 수 없습니다.</p>";
    } else {
        new Chart(ctx, {
            type: 'line',
            data: {
                labels: chartLabels,
                datasets: [{
                    label: '값 변화 추이',
                    data: chartData,
                    borderColor: 'rgba(255, 99, 132, 1)', 
                    backgroundColor: 'rgba(255, 99, 132, 0.4)',
                    borderWidth: 2,
                    tension: 0.3, 
                    pointRadius: 4,
                    pointBackgroundColor: 'rgba(255, 99, 132, 1)'
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: true,
                scales: {
                    x: {
                        type: 'category', 
                        title: { display: true, text: '시간 (HH:MM KST)', font: { size: 14 } }
                    },
                    y: {
                        title: { display: true, text: '값', font: { size: 14 } },
                        beginAtZero: false,
                        ticks: {
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
                        callbacks: {
                            label: function(context) {
                                let label = context.dataset.label || '';
                                if (label) {
                                    label += ': ';
                                }
                                if (context.parsed.y !== null) {
                                    label += context.parsed.y.toString().replace(/\B(?=(\d{3})+(?!\d))/g, ",");
                                }
                                return label;
                            }
                        }
                    }
                }
            }
        });
    }
    </script>
</body>
</html>
CHART_END
