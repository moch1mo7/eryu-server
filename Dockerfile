# eryu — 自托管网易云音乐服务（零外部依赖，纯 Python stdlib）
FROM python:3.12-slim

WORKDIR /app

# 复制服务端代码 + 前端
COPY server/eryu.py /app/
COPY server/analyze_song.py /app/
COPY client/ /app/client/

# 数据目录
RUN mkdir -p /app/data/music_cache

# 启动脚本：从环境变量写入配置 → 启动服务
RUN echo '#!/bin/bash\n\
if [ -n "$MUSIC_U" ]; then\n\
  echo "MUSIC_U=$MUSIC_U" > /app/.netease_cred\n\
  echo "[eryu] MUSIC_U configured"\n\
else\n\
  echo "[eryu] WARNING: MUSIC_U not set — search/play wont work"\n\
fi\n\
if [ -n "$ERYU_AUTH_TOKEN" ]; then\n\
  echo "$ERYU_AUTH_TOKEN" > /app/.secret\n\
  echo "[eryu] Auth token configured"\n\
fi\n\
exec python /app/eryu.py\n\
' > /app/start.sh && chmod +x /app/start.sh

EXPOSE 9090
ENV PORT=9090
CMD ["/app/start.sh"]
