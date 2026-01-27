COPY ../../../../../../ /home/developer/fc-nixos
RUN chown developer: -R /home/developer/fc-nixos
RUN rm -rf /home/developer/fc-nixos/channels
# un-confuse nix flake references
RUN rm -rf /home/developer/fc-nixos/.git
RUN /home/developer/fc-nixos/dev-setup
