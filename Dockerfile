ARG PRIVATE_REGISTRY=ci.ru.aegean.gr:5000
FROM ${PRIVATE_REGISTRY}/base20:ruby

USER root
RUN apt-get -y update && apt-get -y install  mariadb-server mariadb-client libmysqlclient-dev postgresql postgresql-contrib
#RUN systemctl enable postgresql && systemctl enable mariadb && systemctl enable redis-server
#RUN echo "sudo service postgresql start" >> /etc/bash.bashrc
#RUN echo "sudo service mysql start" >> /etc/bash.bashrc
#RUN echo "sudo redis-server /etc/redis/redis.conf" >> /etc/bash.bashrc

ENV PGUSER=postgres
ENV PGPORT=5432
ENV PGHOST=localhost

RUN sed -i -e '/local.*peer/s/postgres/all/' -e 's/peer\|md5/trust/g' /etc/postgresql/*/main/pg_hba.conf
    #&& \
#    service postgresql start && \
#    until pg_isready --username=postgres --host=localhost; do sleep 1; done && \
#    echo "echo \"ALTER USER postgres PASSWORD '${GEM_SERVER_KEY}';\" | psql"

USER user

ARG RUBY_VERSION_TO_INSTALL1=2.7.8
RUN rbenv install ${RUBY_VERSION_TO_INSTALL1} && rbenv global ${RUBY_VERSION_TO_INSTALL1} \
&& rbenv rehash && gem install bundler

ARG RUBY_VERSION_TO_INSTALL2=3.0.6
RUN rbenv install ${RUBY_VERSION_TO_INSTALL2} && rbenv global ${RUBY_VERSION_TO_INSTALL2} \
&& rbenv rehash && gem install bundler

ARG RUBY_VERSION_TO_INSTALL3=3.1.4
RUN rbenv install ${RUBY_VERSION_TO_INSTALL3} && rbenv global ${RUBY_VERSION_TO_INSTALL3} \
&& rbenv rehash && gem install bundler

ARG RUBY_VERSION_TO_INSTALL4=3.2.2
RUN rbenv install ${RUBY_VERSION_TO_INSTALL4} && rbenv global ${RUBY_VERSION_TO_INSTALL4} \
&& rbenv rehash && gem install bundler

ARG RUBY_VERSION_TO_INSTALL4=3.3.0
RUN rbenv install ${RUBY_VERSION_TO_INSTALL4} && rbenv global ${RUBY_VERSION_TO_INSTALL4} \
&& rbenv rehash && gem install bundler

USER root

RUN git config --global --add safe.directory /root/hyperstack
