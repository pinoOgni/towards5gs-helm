FROM towards5gs/ueransim-ue:v3.2.6 

# RUN apt update && apt-get install -y iperf3

COPY wrapper_ue_traffic.sh /ueransim/build/
RUN chmod +x /ueransim/build/wrapper_ue_traffic.sh
# CMD ["/bin/bash", "-c", "./ueransim/build/wrapper_ue_traffic.sh"]

