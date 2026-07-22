# eryu — 自托管网易云音乐服务
FROM python:3.12-slim

WORKDIR /app

# 复制服务端代码
COPY server/eryu.py /app/
COPY server/analyze_song.py /app/
COPY server/sync_supabase.py /app/
COPY client/ /app/client/

# 数据目录
RUN mkdir -p /app/data/music_cache

# 启动脚本
RUN echo '#!/bin/bash\n\
# MUSIC_U cookie\n\
if [ -n "$MUSIC_U" ]; then\n\
  echo "MUSIC_U=$MUSIC_U" > /app/.netease_cred\n\
  echo "[eryu] MUSIC_U configured"\n\
else\n\
  echo "[eryu] WARNING: MUSIC_U not set"\n\
fi\n\
# Auth token\n\
if [ -n "$ERYU_AUTH_TOKEN" ]; then\n\
  echo "$ERYU_AUTH_TOKEN" > /app/.secret\n\
  echo "[eryu] Auth token configured from env"\n\
fi\n\
# Supabase 同步 — 后台 Python 进程（启动恢复 + 定时备份）\n\
python3 /app/sync_supabase.py &\n\
# 自唤醒：每 9 分钟 self-ping\n\
(while true; do sleep 540; wget -q -O /dev/null http://localhost:9090/health || true; done) &\n\
exec python /app/eryu.py\n\
' > /app/start.sh && chmod +x /app/start.sh

EXPOSE 9090
ENV PORT=9090
CMD ["/app/start.sh"]
