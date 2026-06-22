#!/bin/bash
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
nvm use 20 > /dev/null 2>&1

echo "正在生成静态文件..."
hexo clean && hexo generate
echo "正在同步到服务器..."
rsync -avz --delete -e "ssh -i ~/.ssh/id_rsa" public/ azureuser@70.153.16.253:/var/www/blog/
echo "部署完成！"
