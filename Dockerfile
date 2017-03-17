FROM reg.huobi.io/nodejs
MAINTAINER bearice@icybear.net

RUN npm install -g coffeescript@next
CMD ["coffee","/opt/daikon-ipam/main.coffee"]
WORKDIR /opt/daikon-ipam
ADD . /opt/daikon-ipam
