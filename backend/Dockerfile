# Lambda コンテナイメージ（ビルドは backend/ をコンテキストにする）
FROM public.ecr.aws/lambda/python:3.12

# Lambda は /tmp 以外が読み取り専用なので、yfinance 等のキャッシュ先を /tmp に向ける
ENV HOME=/tmp \
    XDG_CACHE_HOME=/tmp

COPY requirements.txt requirements-lambda.txt ${LAMBDA_TASK_ROOT}/
RUN pip install --no-cache-dir -r ${LAMBDA_TASK_ROOT}/requirements-lambda.txt

COPY . ${LAMBDA_TASK_ROOT}/

CMD ["lambda_handler.handler"]
