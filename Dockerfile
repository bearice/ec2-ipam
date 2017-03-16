FROM reg.huobi.io/nodejs
MAINTAINER bearice@icybear.net

ADD . /opt/daikon-ipam
RUN npm install -g coffeescript@next
CMD ["coffee","/opt/daikon-ipam/main.coffee"]
WORKDIR /opt/daikon-ipam
