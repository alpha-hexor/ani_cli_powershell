$main_link="https://gogoanime.ar"
function create_aes($key){
    $aes=New-Object "System.Security.Cryptography.AesManaged"
    $aes.Mode = [System.Security.Cryptography.CipherMode]::CBC
    $aes.IV = [System.Text.Encoding]::UTF8.GetBytes("3134003223491201")
    $aes.Key = [System.Text.Encoding]::UTF8.GetBytes($key)
    $aes
}

function aes_encrypt($plaintext){
    #convert to bytes
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($plaintext)
    $aes= create_aes "37911490979715163134003223491201"
    $encryptor = $aes.CreateEncryptor()
    $encrypted_data = $encryptor.TransformFinalBlock($bytes, 0, $bytes.Length);
    [System.Convert]::ToBase64String($encrypted_data)

}
function aes_decrypt($key,$encrypted_text){
    $bytes = [System.Convert]::FromBase64String($encrypted_text)
    $aes = create_aes $key
    $decryptor=$aes.CreateDecryptor()
    $decrypted_data = $decryptor.TransformFinalBlock($bytes, 16, $bytes.Length - 16);
    [System.Text.Encoding]::UTF8.GetString($decrypted_data).Trim([char]0)
}

function get_group($pattern,$content){
    $match = Select-String $pattern -InputObject $content

    $match.matches.groups[1].value
}
function get_re($pattern,$content){
    $match = Select-String $pattern -InputObject $content
    $match.matches.groups[0].value
}

function search_anime($name){
    $name = $name.Replace(" ","%20")
    $search_url=$search_url=$main_link+"/search.html?keyword=$name"
    $response = Invoke-WebRequest -Uri $search_url
    $anime_results = $response.ParsedHtml.getElementsByClassName('name') | ForEach-Object { $_.getElementsByTagName('a')} |Select-Object -Expand nameProp
    
    Write-Host "[*]Results: "
    for($i=0;$i -lt $anime_results.Length;$i++){
        Write-Host $i":" -NoNewline
        Write-Host $anime_results[$i]
    }

    $p = Read-Host -Prompt "[*]Enter index"
    $anime_results[$p]
}

function search_ep($name){
    $link=$main_link+"/category/$name"
    $response = Invoke-WebRequest -Uri $link
    $eps = get_group "ep_start = '0' ep_end = '(\d+)'>" $response.Content
    $eps
}

function get_quality($link){
    $j=0
    $response = Invoke-WebRequest -Uri $link
    $qualities = Select-String "RESOLUTION=[0-9]+x([0-9]+)" -InputObject [string]$response.rawcontent -AllMatches | ForEach-Object {$_.matches.Groups.value}
    if($qualities.Length -ne 0){
        $l = Select-String ".*\.m3u8" -InputObject $response.rawcontent -AllMatches | ForEach-Object {$_.matches.Groups.value}
        for($i=1;$i -lt $qualities.Length ; $i+=2){
            Write-Host $j":" -NoNewline
            Write-Host $qualities[$i]"p"
            $j++
        }
        $p = Read-Host -Prompt "[*]Enter your choice"
        $f_link = $l[$p]
        if($f_link -match "https://"){
            $f_link = $f_link
        }
        else{
            $f_link = $link.Replace($link.Split("/")[-1],$f_link)
        }
    }
    else{
        $f_link = $link
    }

    $f_link
}

function get_final_link($link){
    $response = Invoke-WebRequest -Uri $link
    $gogo_link = "https:" + (get_group 'data-video=\"(//gogohd.net/streaming.php?.*)\" >' $response.Content)
    $gogo_id = get_group 'id=(.*)\&' $gogo_link
    $response = Invoke-WebRequest -Uri $gogo_link
    $crypto_data = get_group 'data-value=\"(.*)\"' $response.Content
    $raw_crypto = aes_decrypt "37911490979715163134003223491201" $crypto_data
    $full_crypto_shit = get_re '\&mip=.*' $raw_crypto
    $id = aes_encrypt $gogo_id

    #payload for ajax
    $full_payload = "$id$full_crypto_shit&alias=$gogo_id"

    $header=@{
        'x-requested-with' = 'XMLHttpRequest'
    }
    $response= Invoke-WebRequest -Uri "https://gogohd.net/encrypt-ajax.php?id=$full_payload" -Headers $header
    $x = $response.Content | ConvertFrom-Json

    $link = (aes_decrypt "54674138327930866480207815084989" $x[0].data).Trim("\\\\")
    $final_link = (get_group 'file\":\"([^\"]*)' $link).Replace('\/','/')
    $streaming_link = get_quality $final_link
    $streaming_link 
}

function stream_episode($name,$ep_to_watch,$last_ep){
    $anime_url=$main_link+"/$name-episode-$ep_to_watch"
    $s = get_final_link $anime_url
    Start-Process mpv -ArgumentList "$s --force-media-title='$name-ep-$ep_to_watch'"

    #for next episode
    if(([int]$ep_to_watch+1) -le [int]$last_ep){
        $x = Read-Host -Prompt "[*]Do you want to start next ep(y/n)"
        if($x -like "n"){
            Exit
        }
        $next_ep = [int]$ep_to_watch +1
        stream_episode $name $next_ep $last_ep
    }



}

$name=Read-Host -Prompt "[*]Enter anime name"
$anime_to_watch =search_anime $name
$last_ep = search_ep $anime_to_watch
$p = read-host -Prompt "[*]Available Episode(1-$last_ep)"
stream_episode $anime_to_watch $p $last_ep
