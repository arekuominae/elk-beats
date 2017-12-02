# Dockerfile for ELK stack
# Elasticsearch 6.0, Logstash 6.0, Kibana 6.0

# Build with:
# docker build -t <repo-user>/elk .

# Run with:
# docker run -p 5601:5601 -p 9200:9200 -p 5000:5000 -it --name elk <repo-user>/elk

FROM phusion/baseimage
MAINTAINER Thomas Cooper http://www.rackdeploy.com
# Built on the original sebp/elk by Sebastien Pujadas http://pujadas.net
ENV REFRESHED_AT 2016-01-23

# set environment variables
ENV DEBIAN_FRONTEND=noninteractive HOME="/root" TERM=xterm APACHE_RUN_USER=www-data APACHE_RUN_GROUP=www-data APACHE_LOG_DIR="/var/log/apache2" APACHE_LOCK_DIR="/var/lock/apache2" APACHE_PID_FILE="/var/run/apache2.pid"

CMD ["/sbin/my_init"]

# fix a Debianism of the nobody's uid being 65534
RUN usermod -u 99 nobody \
&& usermod -g 100 nobody

# set startup files
RUN mkdir -p /etc/service/apache \
&& mv /root/apache.sh /etc/service/apache/run \
&& chmod +x /etc/service/apache/run \
&& mv /root/firstrun.sh /etc/my_init.d/firstrun.sh \
&& chmod +x /etc/my_init.d/firstrun.sh

# Enable apache mods.
RUN a2enmod php5 \
&& a2enmod rewrite 

# Update the PHP.ini file, enable <? ?> tags and quieten logging.
RUN sed -i "s/short_open_tag = Off/short_open_tag = On/" /etc/php5/apache2/php.ini \
&& sed -i "s/error_reporting = .*$/error_reporting = E_ERROR | E_WARNING | E_PARSE/" /etc/php5/apache2/php.ini \
&& mv /root/apache-config.conf /etc/apache2/sites-enabled/000-default.conf

###############################################################################
#                                INSTALLATION
###############################################################################

### install Elasticsearch

RUN apt-get update -qq \
 && apt-get install -qqy curl \
 && apt-get install apt-transport-https

RUN curl https://artifacts.elastic.co/GPG-KEY-elasticsearch | apt-key add -
RUN echo "deb https://artifacts.elastic.co/packages/6.x/apt stable main" | tee -a /etc/apt/sources.list.d/elastic-6.x.list
# OLD RUN echo deb http://packages.elasticsearch.org/elasticsearch/2.x/debian stable main > /etc/apt/sources.list.d/elasticsearch-2.x.list
RUN echo deb https://packages.elastic.co/beats/apt stable main > /etc/apt/sources.list.d/beats.list

RUN apt-get update -qq \
 && apt-get install -qqy \
		elasticsearch \
		openjdk-8-jre

### install Logstash

ENV LOGSTASH_HOME /opt/logstash
ENV LOGSTASH_PACKAGE logstash-6.0.0.tar.gz

# OLD ENV LOGSTASH_PACKAGE logstash-6.0.0.tar.gz

RUN mkdir ${LOGSTASH_HOME} \ 
 # OLD && curl -O https://download.elasticsearch.org/logstash/logstash/${LOGSTASH_PACKAGE} \
 && curl -O https://artifacts.elastic.co/downloads/logstash/${LOGSTASH_PACKAGE} \
 && tar xzf ${LOGSTASH_PACKAGE} -C ${LOGSTASH_HOME} --strip-components=1 \
 && rm -f ${LOGSTASH_PACKAGE} \
 && groupadd -r logstash \
 && useradd -r -s /usr/sbin/nologin -d ${LOGSTASH_HOME} -c "Logstash service user" -g logstash logstash \
 && mkdir -p /var/log/logstash /etc/logstash/conf.d \
 && chown -R logstash:logstash ${LOGSTASH_HOME} /var/log/logstash

ADD ./logstash-init /etc/init.d/logstash
RUN sed -i -e 's#^LS_HOME=$#LS_HOME='$LOGSTASH_HOME'#' /etc/init.d/logstash \
 && chmod +x /etc/init.d/logstash


### install Kibana

ENV KIBANA_HOME /opt/kibana
ENV KIBANA_PACKAGE kibana-6.0.0-linux-x86_64.tar.gz
# OLD ENV KIBANA_PACKAGE kibana-4.3.1-linux-x64.tar.gz


RUN mkdir ${KIBANA_HOME} \
 # OLD && curl -O https://download.elasticsearch.org/kibana/kibana/${KIBANA_PACKAGE} \
 && curl -O https://artifacts.elastic.co/downloads/kibana/${KIBANA_PACKAGE} \
 && tar xzf ${KIBANA_PACKAGE} -C ${KIBANA_HOME} --strip-components=1 \
 && rm -f ${KIBANA_PACKAGE} \
 && groupadd -r kibana \
 && useradd -r -s /usr/sbin/nologin -d ${KIBANA_HOME} -c "Kibana service user" -g kibana kibana \
 && mkdir -p /var/log/kibana \
 && chown -R kibana:kibana ${KIBANA_HOME} /var/log/kibana

ADD ./kibana-init /etc/init.d/kibana
RUN sed -i -e 's#^KIBANA_HOME=$#KIBANA_HOME='$KIBANA_HOME'#' /etc/init.d/kibana \
 && chmod +x /etc/init.d/kibana


### install Beats

RUN apt-get install filebeat
RUN update-rc.d filebeat defaults 95 10


###############################################################################
#                               CONFIGURATION
###############################################################################

### configure Elasticsearch

ADD ./elasticsearch.yml /etc/elasticsearch/elasticsearch.yml


### configure Logstash

# certs/keys for Beats and Lumberjack input
RUN mkdir -p /etc/pki/tls/certs && mkdir /etc/pki/tls/private
ADD ./logstash-forwarder.crt /etc/pki/tls/certs/logstash-forwarder.crt
ADD ./logstash-forwarder.key /etc/pki/tls/private/logstash-forwarder.key
ADD ./logstash-beats.crt /etc/pki/tls/certs/logstash-beats.crt
ADD ./logstash-beats.key /etc/pki/tls/private/logstash-beats.key

# filters
ADD ./01-lumberjack-input.conf /etc/logstash/conf.d/01-lumberjack-input.conf
ADD ./02-beats-input.conf /etc/logstash/conf.d/02-beats-input.conf
ADD ./10-syslog.conf /etc/logstash/conf.d/10-syslog.conf
ADD ./30-output.conf /etc/logstash/conf.d/30-output.conf

# filebeat
ADD ./filebeat.yml /etc/filebeat/filebeat.yml

# timezone fix
ADD ./timezone_fix /usr/local/bin/timezone_fix
RUN chmod +x /usr/local/bin/timezone_fix

###############################################################################
#                                   START
###############################################################################

ADD ./start.sh /usr/local/bin/start.sh
RUN chmod +x /usr/local/bin/start.sh

# OLD EXPOSE 5601 9200 9300 5000 5044
EXPOSE 80/tcp 5140/udp 9200/tcp 9300 5000 5044
VOLUME /var/lib/elasticsearch

CMD [ "/usr/local/bin/start.sh" ]
