#!/bin/sh

# 🚨 수정: TZ 환경 변수를 'Asia/Seoul'로 설정하여 date 명령이 정확히 KST를 출력하도록 강제합니다.
export TZ='Asia/Seoul'

# 1. 스크립트 실행 시간 획득 (이제 정확히 KST 시간이 출력됩니다)
EXEC_TIME=$(date '+%Y-%m-%d %H:%M:%S KST')

# 2. 상수 정의
URL="https://sss.wemixplay.com/en/lygl?wmsso_sign=check"
CONSTANT_VALUE=50000
MULTIPLIER=100

# 3. 데이터 가져오기 및 타겟 라인 추출
TARGET_LINE=$(curl -s "$URL" | html2text | grep 'WEMIX = \$')

# 4. WEMIX 총액 (A) 추출 및 정제 (예: $48,918 -> 48918)
A_RAW=$(echo "$TARGET_LINE" | grep -o '\$[0-9]*,[0-9]*' | head -n 1)
A_NUM_TEMP=$(echo "$A_RAW" | tr -d '$,')
# *핵심*: 잘못된 계산을 유발하는 마지막 문자 '1'을 제거합니다.
A_NUM=$(echo "$A_NUM_TEMP" | sed 's/.$//')


# 5. WEMIX 단가 (B) 추출 및 정제 (예: $0.5672 -> 0.5672)
B_RAW=$(echo "$TARGET_LINE" | grep -o '\$[0-9]*\.[0-9]\+' | head -n 1)
B_NUM=$(echo "$B_RAW" | tr -d '$')


# 6. 필수 값 누락 확인 (오류 방지)
if [ -z "$A_NUM" ] || [ -z "$B_NUM" ]; then
    echo "오류: 유동적인 두 값을 모두 추출하지 못했습니다." >&2
    exit 1
fi

# 7. 계산 (bc 사용)
CALC_EXPRESSION="$A_NUM - ($CONSTANT_VALUE * $B_NUM)"
FINAL_CALC_EXPRESSION="($CALC_EXPRESSION) * $MULTIPLIER"

# scale=0: 소수점 이하를 표시하지 않습니다.
RESULT=$(echo "scale=0; $FINAL_CALC_EXPRESSION / 1" | bc)

# 8. 최종 결과 포맷팅 (쉼표 추가)
FINAL_RESULT_FORMATTED=$(echo "$RESULT" | sed -E ':a;s/^([0-9]+)([0-9]{3})/\1,\2/;ta')

# 9. 최종 출력
echo "$EXEC_TIME : $FINAL_RESULT_FORMATTED"
