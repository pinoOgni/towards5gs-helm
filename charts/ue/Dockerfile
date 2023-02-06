FROM towards5gs/ueransim-ue:v3.2.6 

# RUN apt update && apt-get install -y iperf3

COPY wrapper_pino.sh /ueransim/build/
RUN chmod +x /ueransim/build/wrapper_pino.sh
# CMD ["/bin/bash", "-c", "./ueransim/build/wrapper_pino.sh"]
# CMD ["/bin/bash", "-c", "touch /ueransim/build/A"] # non va
