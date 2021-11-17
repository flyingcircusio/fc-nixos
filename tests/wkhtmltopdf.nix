import ./make-test-python.nix ({ lib, pkgs, testlib, ... }:
let
  sample = pkgs.writeText "sample.html"
      ''
      <!DOCTYPE html>
      <html>
      <head>
        <title>Infos</title>
        <meta charset="UTF-8" />
        <style type="text/css">
          * {
            font-family: Arial,sans-serif;
            font-size: 13px;
          }
          sup {
            vertical-align: super;
            font-size: 9px;
          }
          table {
            border-collapse: collapse;
          }
          tr {
            page-break-inside: avoid;
          }
          .striped td,
          .striped th {
            background: #eeeeee;
          }
          td {
            border: 1px solid #fff;
            vertical-align: top;
            padding: 0px 4px;
          }
          th {
            border: 1px solid #fff;
            vertical-align: top;
            padding: 0px 4px;
            font-weight: bold;
            text-align: left;
            background: #fff;
          }
          thead {
            display: table-header-group;
          }
          .reseller-heading {
            background: #e0e0e0;
          }
          thead th {
            border-bottom-color: #000000;
          }
        </style>
      </head>
      <body>
      <table style="width: 100%;">
        <thead>
        <tr>
          <th>Header 1</th>
          <th colspan="2">Header 2</th>
          <th>Header 3-<br>subheader</th>
          <th>Header 4<br>subheader</th>
          <th>Header5-<br>subheader</th>
          <th colspan="2">Foo&nbsp;/&nbsp;foo</th>
        </tr>
        </thead>
        <tbody>
            <tr>
            <th class="reseller-heading" colspan="8">
              Test
            </th>
          </tr>
                        <tr >
                <!-- 1 -->
                <td>Test Produkt<sup>1</sup></td>           <!-- 2 -->
                <td style="text-align: right;">1.000</td>
                <td style="text-align: right;">50.000</td>
                <!-- 3 -->
                <td style="text-align: right;">50,00 €</td>
                <!-- 4 -->
                <td style="text-align: right;"></td>
                <!-- 5 -->
                          <!-- 6 -->
                <td style="text-align: right;"></td>
                <!-- 7 -->
                <td style="text-align: right;">50 %</td>
                <td style="text-align: right;">50 %</td>
              </tr>
                    <tr >
                <!-- 1 -->
                <td></td>           <!-- 2 -->
                <td style="text-align: right;">50.001</td>
                <td style="text-align: right;">100.000</td>
                <!-- 3 -->
                <td style="text-align: right;">100,00 €</td>
                <!-- 4 -->
                <td style="text-align: right;"></td>
                <!-- 5 -->
                          <!-- 6 -->
                <td style="text-align: right;">50,00 €</td>
                <!-- 7 -->
                <td style="text-align: right;">50 %</td>
                <td style="text-align: right;">50 %</td>
              </tr>
                    </tbody>
      </table>
      <p>
        <b>ERLÄUTERUNG</b>
      </p>
      <ul>
        <li>Lorem di lorem la lorem</li>
        <li>Lorem di lorem la lorem</li>
        <li>Lorem di lorem la lorem</li>
        <li>Lorem di lorem la lorem</li>
        <li>Lorem di lorem la lorem</li>
        <li>Lorem di lorem la lorem</li>
        </ul>
        <p><b>Anbieter Zusatzinformationen</b></p>
            <p><b>Test Anbieter</b></p>
          <ol>
                    <li value="1">Test</li>
                </ol>
        
      </body>
      </html>
      '';
in 
{
  machine =
    { pkgs, lib, config, ... }:
    {
      imports = [ ../nixos ../nixos/roles ];

      services.telegraf.enable = false;

    };
      
  testScript = ''
    print("${pkgs.wkhtmltopdf_0_12_6}")
    machine.succeed('${pkgs.wkhtmltopdf_0_12_6}/bin/wkhtmltopdf --orientation Landscape --footer-spacing 0 --header-spacing 5 ${sample} /tmp/sample1.pdf')
    machine.succeed('${pkgs.poppler_utils}/bin/pdftohtml -s -fontfullname /tmp/sample1.pdf')
    _, output = machine.execute('cat sample1-html.html')
    print(output)
    # This is kind of insane, but the PDF appears to create a *bold* header
    # (and poppler detecting this) by providing the character twice 
    # with a shift of 1 px.
    assert output.count('Header&#160;3') == 2
  '';
})
