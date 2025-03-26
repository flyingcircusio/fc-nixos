COPY ../../../../../../../fc-nixos /home/developer/
RUN chown developer: -R /home/developer/fc-nixos
RUN rm -rf /home/developer/fc-nixos/channels
RUN /home/developer/fc-nixos/dev-setup
