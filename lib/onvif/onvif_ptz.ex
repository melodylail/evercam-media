defmodule EvercamMedia.ONVIFPTZ do

  alias EvercamMedia.ONVIFClient

  def get_nodes(url, username, password) do
    ptz_request(url, "GetNodes", 
                "/env:Envelope/env:Body/tptz:GetNodesResponse", username, password)
   end

  def get_configurations(url, username, password) do
    ptz_request(url, "GetConfigurations", 
                "/env:Envelope/env:Body/tptz:GetConfigurationsResponse", username, password)
  end

  def get_presets(url, username, password, profile_token) do
    {:ok, response} = ptz_request(url, "GetPresets", 
                                  "/env:Envelope/env:Body/tptz:GetPresetsResponse", 
                                  username, password,
                                  "<ProfileToken>#{profile_token}</ProfileToken>")
    {:ok, Map.put(%{}, 
                  "Presets",
                  response
                  |>  Map.get("Preset")
                  |>  Enum.filter(&(Map.get(&1, "Name") != nil))
          )
        }
  end

  def get_status(url, username, password, profile_token) do
    ptz_request(url, "GetStatus", 
               "/env:Envelope/env:Body/tptz:GetStatusResponse",
               username, password,
               "<ProfileToken>#{profile_token}</ProfileToken>")
  end


  def goto_preset(url, username, password, profile_token, preset_token, speed \\ []) do
    ptz_request(url, "GotoPreset", "/env:Envelope/env:Body/tptz:GotoPresetResponse", 
                username, password,
                "<ProfileToken>#{profile_token}</ProfileToken>
                 <PresetToken>#{preset_token}</PresetToken>"
		 <> case pan_tilt_zoom_vector speed do
                      "" -> ""
		      vector -> "<Speed>#{vector}</Speed>"
                    end)
  end
 
  def relative_move(url, username, password, profile_token, translation, speed \\ []) do
    ptz_request(url, "RelativeMove", 
                "/env:Envelope/env:Body/tptz:GotoPresetResponse",username, password,
                "<ProfileToken>#{profile_token}</ProfileToken>
                <Translation>#{pan_tilt_zoom_vector translation}</Translation>"
	        <> case pan_tilt_zoom_vector speed do
                     "" -> ""
	             vector -> "<Speed>#{vector}</Speed>"
	       end)
  end

  
  
  def continuous_move(url, username, password, profile_token, velocity \\ []) do
    ptz_request(url, "ContinousMove", 
                "/env:Envelope/env:Body/tptz:ContinuousMoveResponse", username, password,
                "<ProfileToken>#{profile_token}</ProfileToken>"
	        <> case pan_tilt_zoom_vector velocity do
                     "" -> ""
	                  vector -> "<Velocity>#{vector}</Velocity>"
               end)
  end


  def goto_home_position(url, username, password, profile_token, speed \\ []) do
    ptz_request(url,"GotoHomePosition", 
                "/env:Envelope/env:Body/tptz:GotoHomePositionResponse", username, password,
                "<ProfileToken>#{profile_token}</ProfileToken>"
                <> case pan_tilt_zoom_vector speed do
                     "" -> ""
	                   vector  -> "<Speed>#{vector}</Speed>"
                end)

  end
 
  def remove_preset(url, username, password, profile_token, preset_token) do
    ptz_request(url, "RemovePreset", 
                "/env:Envelope/env:Body/tptz:RemovePresetResponse", username, password,
                "<ProfileToken>#{profile_token}</ProfileToken>
                <PresetToken>#{preset_token}</PresetToken>")
  end

  def set_preset(url, username, password, profile_token, preset_name \\ "", preset_token \\ "") do
    ptz_request(url, "SetPreset", 
                "/env:Envelope/env:Body/tptz:SetPresetResponse", username, password,
                "<ProfileToken>#{profile_token}</ProfileToken>"
                <> case preset_name do
                     "" -> ""
                     _ -> "<PresetName>#{preset_name}</PresetName>"
                   end
                <> case preset_token do
                     "" -> ""
                     _ -> "<PresetToken>#{preset_token}</PresetToken>"
                    end)
  end

  def set_home_position(url, username, password, profile_token) do
    ptz_request(url ,"SetHomePosition", 
                "/env:Envelope/env:Body/tptz:SetHomePositionResponse", username, password,
                "<ProfileToken>#{profile_token}</ProfileToken>")

  end
						 
  def stop(url, username, password, profile_token) do
    ptz_request(url, "Stop", 
                "/env:Envelope/env:Body/tptz:StopResponse", 
                username, password,
                "<ProfileToken>#{profile_token}</ProfileToken>")
  end


  def pan_tilt_zoom_vector(vector) do
    pan_tilt = case {vector[:x], vector[:y]}  do
                {nil,_} -> ""
                {_, nil} -> ""
                {x,y}  -> "<PanTilt x=\"#{x}\" y=\"#{y}\" xmlns=\"http://www.onvif.org/ver10/schema\"/>"
	      end
    zoom = case vector[:zoom] do
             nil -> ""									 
             zoom  -> "<Zoom x=\"#{zoom}\"  xmlns=\"http://www.onvif.org/ver10/schema\"/>"
           end
    pan_tilt <> zoom
  end

  defp ptz_request(url, method, xpath, username, password, parameters \\ "") do
    ONVIFClient.onvif_call(url, :ptz, method, xpath, username, password, parameters) 
  end
end