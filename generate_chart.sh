#!/bin/bash



# 1. 데이터 파싱 및 JavaScript 배열 포맷으로 변환 (JS_DATA)
JS_DATA=$(awk -F ' : ' '{ 
    # 쉼표 제거 및 JSON 객체 포맷팅
    gsub(/,/, "", $2); 
    if (NR==1) {printf "{"} else {printf ", "}; 
    printf "x: \"%s\", y: %s}", $1, $2 
}' result.txt)

# 2. HTML 파일 생성
cat << CHART_END > chart.html
<!DOCTYPE html>
<html>
<head>
    <title>스트리밍 목록 업데이트 차트</title>
    <script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.3/dist/chart.umd.min.js"></script>
    <script src="https://cdn.jsdelivr.net/npm/chartjs-adapter-moment@1.0.1/dist/chartjs-adapter-moment.min.js"></script>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        #chartContainer { width: 90%; max-width: 1000px; margin: auto; }
    </style>
</head>
<body>
    <h1>스트리밍 데이터 변화 추이 (KST)</h1>
    <p>최근 업데이트 시간: $(tail -n 1 result.txt | awk -F ' : ' '{print $1}')</p>
    <div id="chartContainer">
        <canvas id="timeSeriesChart"></canvas>
    </div>
    
    <script>
    // JS_DATA를 직접 삽입하고, 외부에서 배열 괄호([])를 추가
    const chartData = [${JS_DATA}]; 

    const ctx = document.getElementById('timeSeriesChart').getContext('2d');
    
    new Chart(ctx, {
        type: 'line',
        data: {
            datasets: [{
                label: '값 변화 추이',
                data: chartData,
                borderColor: 'rgba(54, 162, 235, 1)',
                backgroundColor: 'rgba(54, 162, 235, 0.2)',
                borderWidth: 2,
                tension: 0.1,
                pointRadius: 3
            }]
        },
        options: {
            responsive: true,
            scales: {
                x: {
                    type: 'time',
                    adapters: {
                        date: {
                            zone: 'Asia/Seoul'
                        }
                    },
                    time: {
                        unit: 'hour',
                        tooltipFormat: 'yyyy-MM-dd HH:mm:ss KST',
                        displayFormats: {
                            hour: 'MM/DD HH:mm',
                            day: 'MM/DD'
                        }
                    },
                    title: { display: true, text: '시간' }
                },
                y: {
                    title: { display: true, text: '값' },
                    beginAtZero: false,
                    ticks: {
                        callback: function(value) {
                            return value.toString().replace(/\B(?=(\d{3})+(?!\d))/g, ",");
                        }
                    }
                }
            },
            plugins: {
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
    </script>
</body>
</html>
CHART_END
