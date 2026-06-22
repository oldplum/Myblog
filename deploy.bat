@echo off
echo 正在部署博客...
C:\Windows\System32\wsl.exe bash -c "source ~/.bashrc && cd /mnt/d/myblog && ./deploy.sh 2>&1"
echo 部署完成！
pause