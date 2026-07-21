# eryu — 自托管网易云音乐服务（零外部依赖，纯 Python stdlib）
FROM python:3.12-slim

WORKDIR /app

# 复制服务端代码 + 前端
COPY server/eryu.py /app/
COPY server/analyze_song.py /app/
COPY client/ /app/client/

# 数据目录
RUN mkdir -p /app/data/music_cache

# 启动脚本：从环境变量写入配置 → 后台定时 Supabase 同步 → 启动 eryu
RUN echo '#!/bin/bash\n\
if [ -n "$MUSIC_U" ]; then\n\
  echo "MUSIC_U=$MUSIC_U" > /app/.netease_cred\n\
  echo "[eryu] MUSIC_U configured"\n\
else\n\
  echo "[eryu] WARNING: MUSIC_U not set"\n\
fi\n\
if [ -n "$ERYU_AUTH_TOKEN" ]; then\n\
  echo "$ERYU_AUTH_TOKEN" > /app/.secret\n\
  echo "[eryu] Auth token configured"\n\
fi\n\
# Supabase 存档同步（每10分钟上传 + 退出时上传）\n\
if [ -n "$SUPABASE_URL" ] && [ -n "$SUPABASE_SERVICE_ROLE_KEY" ] && [ -n "$SUPABASE_BUCKET" ]; then\n\
  echo "[eryu] Supabase sync configured"\n\
  # 启动时下载\n\
  for f in music_data.json music_memory.json music_playlist.json music_remote.json; do\n\
    curl -s -o /app/data/$f -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" -H "apikey: $SUPABASE_SERVICE_ROLE_KEY" "$SUPABASE_URL/storage/v1/object/$SUPABASE_BUCKET/$f" 2>/dev/null && echo "[sync] ⬇ $f" || true\n\
  done\n\
  # 后台定时上传\n\
  (while true; do sleep 600; for f in /app/data/*.json /app/.netease_cred /app/.secret; do\n\
    [ -f "$f" ] && curl -s -X POST -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" -H "apikey: $SUPABASE_SERVICE_ROLE_KEY" --data-binary "@$f" "$SUPABASE_URL/storage/v1/object/$SUPABASE_BUCKET/$(basename $f)" > /dev/null 2>&1 && echo "[sync] ⬆ $(basename $f)"\n\
  done; done) &\n\
  # 退出时上传\n\
  trap "for f in /app/data/*.json; do [ -f \"$f\" ] && curl -s -X POST -H \"Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY\" -H \"apikey: $SUPABASE_SERVICE_ROLE_KEY\" --data-binary \"@$f\" \"$SUPABASE_URL/storage/v1/object/$SUPABASE_BUCKET/$(basename $f)\" > /dev/null 2>&1; done" EXIT\n\
fi\n\
exec python /app/eryu.py\n\
' > /app/start.sh && chmod +x /app/start.sh

EXPOSE 9090
ENV PORT=9090
CMD ["/app/start.sh"]
